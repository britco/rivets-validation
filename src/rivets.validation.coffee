###
 Rivets Validation
 Framework for providing validation tied to rivets.js
 @Author: Paul Dufour
 @Company: Brit + Co
###

rivets.validation =
	handlers: []

	validatorMessages:
		required: 'This field is required'
		minLength: 'Error in field length'
		maxLength: 'Error in field length'
		length: 'Error in field length'
		rangeLength: 'Error in field length'
		pattern: 'Error in field pattern'
		fn: 'Error in field'
		if: 'Error in field'

	# Default validator functions
	validators:
		required: (field, value, isRequired) ->
			exists = (value? and !_.isEmpty(value))

			if isRequired
				return exists
			else
				# Not required, pass on to next rule
				return true

		minLength: (field, value='', requiredLength) ->
			if value.length < requiredLength
				return false
			else
				return true

		maxlength: (field, value='', requiredLength) ->
			if value.length > requiredLength
				return true
			else
				return false

		rangeLength: (field, value='', lengthRange) ->
			if value.length < lengthRange[0]
				return false
			else if value.length > lengthRange[1]
				return false
			else
				return true

		length: (field, value='', requiredLength) ->
			if value.length is requiredLength
				return true
			else
				return false

		equalTo: (field, value, equalToField) ->
			otherFieldValue = rivets.validation.getValue.call(@, equalToField)

			if value isnt otherFieldValue
				return false
			else
				return true

		pattern: (field, value, pattern) ->
			defaultPatterns =
				number: /^([0-9]+)$/
				email: /^(.+)@(.+){2,}\.(.+){2,}$/

			if typeof pattern isnt 'object'
				if !defaultPatterns[pattern]
					throw new Error "Validator pattern not found: #{pattern}"

				re = defaultPatterns[pattern]

				return re.test(value)


		fn: (field, value, fn, tailing...) ->
			if @model[fn]?
				return @model[fn].call @, value, field, tailing...

	# Get the value of a form input that
	# has been bound to rivets
	getValue: (attr) ->
		for binding in @model.__bindings
			if binding.keypath is attr
				value = $(binding.el).val()

				return value

	# Get the validation rules for an object.
	# Right now the only object possible is
	# a Backbone Model. You can also limit
	# to certain fields by passing in a field.
	getValidation: (obj) ->
		if !obj.validation?
			return {}

		validation = {}

		for field, rules of _.clone(obj.validation, true)
			# Convert all rules to a easier format
			# After conversion, the validation will
			# look like billing_address: [
			# 	name: minLength
			# 	rule: <minLengthFN>
			# 	data: 1
			# 	msg: <min length error>
			# ]
			#
			msg = null
			options = null
			data = null
			rule_name = null
			validation[field] = []
			newObj = {}

			if !_.isArray rules
				if rules.msg?
					msg = rules.msg
					delete rules.msg

				for rule, options of rules
					newObj = {}

					newObj['data'] = options

					newObj['fn'] = rivets.validation.validators[rule]

					newObj['name'] = rule

					if msg?
						newObj['msg'] = msg
					else
						if !_.has(newObj, 'msg')
							newObj['msg'] = rivets.validation.validatorMessages[rule]

					validation[field].push newObj
			else
				for rule in rules
					rule_name = _.first(_.filter(_.keys(rule), (value) -> (value isnt 'msg')))

					if !_.has(rule, 'msg')
						rule['msg'] = rivets.validation.validatorMessages[rule_name]

					newObj =
						fn: rivets.validation.validators[rule_name]
						name: rule_name
						msg: rule.msg
						data: rule[rule_name]

					validation[field].push newObj

		return _.clone(validation, true)

	# Validate an individual object attribute
	# against a group of validators
	validateAttr: (options) ->
		options = _.clone(options, false)
		attr = options.attribute
		model = options.model

		attrs = {}
		attrs[attr] = options.value

		if _.isArray options.validation and !options.validation.length
			delete options.validation

		rivets.validation.validate.call(@, _.extend options,
			validation: rivets.validation.getValidation(model)
			attributes: attrs
			intersection: true
			error: _.wrap(options.error, (fn, args...) =>
				# Return only the relevant errors
				if args.length >= 0
					if _.has(args[0], attr)
						args[0] = args[0][attr]

				fn.call(@, args...)
			)
		)

	# Validate an object's attributes.
	# This will validate every attribute
	# that has been provided
	validate: (options={}) ->
		model = if options?.model? then options.model else null
		validators = _.extend {}, @binder.validators, (options.validators || {})
		attrs = options.attributes || @model.attributes
		validation = _.clone(options.validation)
		success = $.proxy(options.success, @) || Function.prototype
		error = $.proxy(options.error, @) || Function.prototype

		binder = @binder
		binding = @

		# If intersection is provided, only validate the attrs provided
		intersection = options.intersection || false

		for field, rules of validation
			if !_.has(attrs, field)
				delete validation[field]

		if !_.size(validation)
			# No validation present?
			success()

		# Callback for when all the rules have been validated.
		# The only reason for having a callback like this
		# is to allow for async validation calls
		validationComplete = ->
			if _.size(errors) > 0
				# Remove errors if another error has precedence, i.e.:
				# required has precedence over minLength, which
				# has priority over maxLength, etc.
				_.each(errors, (errors, field) ->
					if errors.required?
						if _.has(errors, 'minLength')
							delete errors.minLength

						if _.has(errors, 'maxLength')
							delete errors.maxLength
				)

				error(errors)
			else
				success()

		# Mark the whole validation complete when
		# all the fields have been validated
		fieldResolved = _.after(_.keys(validation).length, validationComplete)

		# Loop through the object's validation
		# rules, and after all fields are
		# validated, return the response to the
		# success / error callback
		errors = {}

		# Loop through each field
		_.each validation, (rules, field) ->
			value = attrs[field]

			# Mark the field as completed when all rules have been validated
			ruleResolved = _.after(_.keys(rules).length, fieldResolved)

			# Loop through each rule
			_.every rules, (rule) ->
				# Method for adding an error to the final errors object
				addError = (err, rule) ->
					if !errors[field]?
						errors[field] = {}

					errors[field][rule] = err

				args = [field, value, rule.data]

				if !rule.fn?
					ruleResolved()
				else
					# Get the result of the validation for this field & rule
					result = rule.fn.call(binding, args...)

					# Resolve the results of functions. Since these
					# could take a while to resolve, they can't
					# be handled like other rules. This functionality
					# allows youto do async validation.
					if(rule.name is 'fn') and (result?.promise? and $.isFunction(result.promise))
						onSucccess = ->
							ruleResolved()

						onFail = ->
							addError(rule.msg, rule.name)
							ruleResolved()

						result
							.success (resp) ->
								if typeof resp is 'object'
									if _.has(resp, 'success')
										if resp.success is false
											return onFail()
								return onSucccess()
							.fail ->
								return onFail()
					else
						if !result
							# Rule failed (in a non-async operation)
							# This means: mark the whole field as resolved
							# And continue to the next field
							addError(rule.msg, rule.name)

							fieldResolved()

							return false
						else
							ruleResolved()

				# Go to the next rule
				return true

		return this

	# jQuery functionality to show / hide error
	# messages whenever inputs are validated
	showError: (options={}) ->
		if !options.message?
			return false

		$(@).addClass('error')
		    .removeClass('valid')
		    .attr('data-error', options.message || '')
		    .nextAll('.msg:not(.valid)').each ->
				$(@).text(options.message)
				$(@).fadeIn()

	hideError: (options) ->
		$(@).removeClass('error')
		    .addClass('valid')
		    .removeAttr('data-error')
		    .nextAll('.msg:not(.valid)').each ->
		    	$(@).fadeOut(20)
		    	$(@).text('')

	validateEl: ->
		model = @model
		key = @keypath

		self = @
		@state = 'processing'

		_.defer =>
			# Run the validation, and then update the attr.
			@binder.validateAttr.call @,
				model: model
				attribute: key
				value: $(@el).val()
				success: (errors) ->
					@state = 'valid'

					$(@el).hideError()

					@publish()
				error: (errors) ->
					@state = 'invalid'

					$(@el).showError message: _.first _.values errors

	# Whenever a value is changed, run it through
	# the validators, and then if everything passes
	# publish the value to the object
	onChange: (e, options) ->
		if $(e.currentTarget).attr('data-silent-change') isnt 'true'
			$(@el).attr('data-previous-value', $(@el).val())

			rivets.validation.validateEl.call(@)

	# Records 'tab in a blank input field' as a change
	onKeydown: (e) ->
		code = e.keyCode || e.which

		value = $(@el).val()

		previous_value = $(@el).attr('data-previous-value')

		initial_keydown = $(@el).attr('data-initial-keydown') || true

		if code is 9
			if initial_keydown is true
				$(@el).attr('data-previous-value', value)
					  .attr('data-initial-keydown', 'false')
					  .attr('data-silent-change', 'true')

				rivets.validation.validateEl.call(@)

				$(@el).removeAttr('data-silent-change')

	# Validate the whole form before submitting
	onSubmit: (e) ->
		# If there are remaining inputs that are invalid, kill the submit
		if @state isnt 'valid'
			# Trigger change on all the inputs
			$(@form).find('input:not(:file), select, textarea').trigger('change')

			e.stopImmediatePropagation()

			return false

	bind: (el) ->
		# Silently validate on first bind
		model = @model
		key = @keypath

		@id = _.uniqueId('rivets_validation_')

		@state = 'processing'

		@binder.validateAttr.call @,
			model: model
			attribute: key
			value: model.get(key)
			success: (errors) ->
				@state = 'valid'
			error: (errors) ->
				@state = 'invalid'

		# Set current value
		$(@el).attr('data-previous-value', @model.get(@keypath))

		# Setup listeners
		@form = $(el).parents("form")

		@currentListener = $(el).on "change.#{@id}", $.proxy(@binder.onChange, @)

		@keydownListener = $(el).on "keydown.#{@id}", $.proxy(@binder.onKeydown, @)

		@submitListener = $(el).parents("form").on("submit.#{@id}", $.proxy(@binder.onSubmit, @))

		@dataSubmitListener = $(el).parents("form").find('a[data-submit="true"]').on("click.#{@id}", $.proxy(@binder.onSubmit, @))

	unbind: (el) ->
		# Cleanup listeners
		$(el).off "change.#{@id}", @currentListener

		$(el).off "keydown.#{@id}", @keydownListener

		$(el).parents('form').off "submit.#{@id}", @submitListener

		$(el).parents("form").find('a[data-submit="true"]').on "click.#{@id}", @dataSubmitListener

		@state = 'valid'

		$(el).hideError()

# The rivets validation is a mixin for rivets, value
rivets.binders.value = _.extend rivets.binders.value, rivets.validation

# JQuery functions for showing and hiding error messages
$.fn.showError = rivets.validation.showError

$.fn.hideError = rivets.validation.hideError