rivets-validation
=================

Example

In the model:
    
    module.exports = class Address extends Model
        validation:
            street_line1:
                required: true
                minLength: 1
            city:
                required: true
                minLength: 1
            state:
                required: true
                minLength: 1
            zipcode:
                required: true
                length: 5
                pattern: 'number'
            name:
                required: true
                minLength: 1



In the template:
    
    <input type="text" data-value="billing_address.name" value="">
