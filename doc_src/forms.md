# Use with Forms and Form builders

We've tried to make your attr_jsons just as easy to work with Rails form builders as ordinary attributes, including treating nested/compound models as if they were Rails associations in forms.

It's worked out pretty well. This is one of the more complex parts of our attr_json code, making it work with all the Rails weirdness on nested params, multi-param attributes (generally used for dates), etc. So if a bug is gonna happen somewhere, it's probably here. But at the moment it looks pretty solid and stable.

We even integration test with [simple_form](https://github.com/plataformatec/simple_form) and [cocoon](https://github.com/nathanvda/cocoon) (see below, some custom config may be required).
You can look at our [stub app used for integration tests](../spec/internal) as an example if you like.

## Standard Rails form builder

### Simple attributes

    attr_json :some_string, :string
    attr_json :some_datetime, :datetime

Use with form builder just as you would anything else.

    f.text_field :some_string
    f.datetime_field :some_datetime

It _will_ work with the weird rails multi-param setting used for date fields.

Don't forget you gotta handle strong params same as you would for any ordinary attribute.


### Embedded/Nested AttrJson::Model attributes

With ordinary rails associations handled in the ordinary Rails way, you use [accepts_nested_attributes_for](http://api.rubyonrails.org/classes/ActiveRecord/NestedAttributes/ClassMethods.html) for associations (to-one or to-many).

You can handle a single or array AttrJson::Model attr_json similarly, but you have to:

* include AttrJson::NestedAttributes in your model, and then
* use our own similar `attr_json_accepts_nested_attributes_for` instead.  It _always_ has `allow_destroy`, and some of the other `accepts_nested_attributes_for` options also don't apply, see method for full options -- we expect you will usually want to use this with the `reject_if: :all_blank` option to ignore hashes with no non-nil values.

```ruby
class Event
  include AttrJson::Model

  attr_json :name
  attr_json :datetime
end
class MyRecord < ActiveRecord::Base
  include AttrJson::Record
  include AttrJson::NestedAttributes

  attr_json :one_event, Event.to_type
  attr_json :many_events, Event.to_type, array: true

  attr_json_accepts_nested_attributes_for :one_event, :many_events, reject_if: :all_blank
end

# In a form template...
<%= form_for(record) do |f| %>
  <%= f.fields_for :one_event do |one_event_f| %>
    <%= one_event_f.text_field :name %>
    <%= one_event_f.datetime_field :datetime %>
  <% end %>

  <%= f.fields_for :many_events do |one_event_f| %>
    <%= one_event_f.text_field :name %>
    <%= one_event_f.datetime_field :datetime %>
  <% end %>
<% end %>
```

It should just work as you are expecting! You have to handle strong params as normal for when dealing with Rails associations, which can be tricky, but it's just the same here.

Note that the `AttrJsons::NestedAttributes` module also adds convenient rails-style `build_` methods for you.  In the case above, you get a `build_one_event` and `build_many_event` (note singularization, cause that's how Rails does) method, which you can use much like Rails' `build_to_one_association` or `to_many_assocication.build` methods. You can turn off creation of the build methods by passing `define_build_method: false` to `attr_json_accepts_nested_attributes_for`.

### Shortcuts for attr_json_accepts_nested_attributes_for

You can automatically add the 'accepts nested attributes' call when you define your attribute, including with additional arguments like `reject_if`.

```ruby
class SomeRecord < ApplicationRecord
  include AttrJson::Record
  include AttrJson::NestedAttributes

  attr_json :one_event, Event.to_type, accepts_nested_attributes: true
  attr_json :many_events, Event.to_type, array: true, accepts_nested_attributes: { reject_if: :all_blank }
end
```

You can also set defaults for the whole class:

```ruby
class SomeRecord < ApplicationRecord
  include AttrJson::Record
  include AttrJson::NestedAttributes

  attr_json_config(default_accepts_nested_attributes_for: { reject_if: :all_blank })

  attr_json :one_event, Event.to_type, accepts_nested_attributes: false # override default
  attr_json :many_events, Event.to_type, array: true
end
```

If you're doing a lot of rails-style nested attributes form handling, the above probably makes sense. More convenient than having to do it each time, or repeat every param in another
long call.

### Nested multi-level/compound embedded models

A model inside a model inside a model?  Some single and some array? No problem, should just work.

Remember to add `include AttrJson::NestedAttributes` to all your AttrJson::Models (or at least non-terminal ones). Remember that Rails strong params have to be dealt with and are confusing here, but you deal with them the same way you would multi-nested associations on a rails form.

## Simple Form

One of the nice parts about [simple_form](https://github.com/plataformatec/simple_form) is how you can just give it `f.input`, and it figures out the right input for you.

AttrJson by default registers  `attr_jsons` as Rails attributes, and provides other appropriate implementations in AttrJson::Model classes, such that simple_form should just work. There are limited CI tests in this project to confirm simple_form stays working.


### Arrays of simple attributes

    attr_json :string_array, :string, array: true

The ActionView+ActiveRecord architecture isn't really setup for an array of "primitives", but we can kind of make it work:

    <% f.object.string_array.each do |str| %>
      <%= f.text_field(:string_array, value: str, multiple: true) %>
    <% end %>

Or with simple_form, perhaps:

    <%= f.input :string_array do %>
        <% f.object.string_array.each do |str| %>
            <%= f.text_field(:string_array, value: str, class: "form-control", multiple: true) %>
        <% end %>
    <% end %>

That will display, submit and update fine, although when you try to handle reporting validation errors, you'll probably only be able to report on the array, not the specific element.

The bigger problem is that if you use some javascript to allow people to add/remove elements,
and they remove _all_ elements, Rails params get no input for this attribute, and instead of setting it to empty array, doesn't touch it as in-memory. This is similar to the problem
with Rails collection checkboxes, and we can use a similar solution, of a hidden input value
making sure there's always at least one value.

    <%= f.hidden_field "string_array[]", "" %>
    <%= f.input :string_array do %>
        <% f.object.string_array.each do |str| %>
            <%= f.text_field(:string_array, value: str, class: "form-control", multiple: true) %>
        <% end %>
    <% end %>

But now we'll get an extra empty string added on to our array on every submit! We need to filter
out empty strings. `attr_json_accepts_nested_attributes_for` has an `_attributes=` method implementation when it recognizes an array of primitives, that simply filteres out empty strings. So! With `attr_json_accepts_nested_attributes_for :string_array`:

    <%= f.hidden_field "string_array_attributes[]", "" %>
    <%= f.input :string_array do %>
        <% f.object.string_array.each do |str| %>
            <%= f.text_field(:string_array_attributes, value: str, class: "form-control", multiple: true) %>
        <% end %>
    <% end %>

This is definitely getting a bit obtuse. You may want to consider an array of AttrJson::Model value types instead -- you can have a model with only one attribute! It can be handled somewhat more conventionally, as above.

## Cocoon

[Cocoon](https://github.com/nathanvda/cocoon) is one easy way to implement js-powered add- and remove-field functionality for to-many associations nested on a form with Rails.

It _almost_ "just works" with nested/compound AttrJson::Model attributes, used with rails `fields_for` form builder as above. But Cocoon is looking for some ActiveRecord-specific methods that don't exist in our AttrJson::Models -- although it doesn't actually matter what these methods return, Cocoon works with our architecture either way.

Include the `AttrJson::Model::CocoonCompat` module in your **AttrJson::Model** classes to get these methods so Cocoon will work.

We have an integration test running a real rails app ensuring both simple_form and cocoon continue to work.

## Reform?

If you would rather use [Reform](https://github.com/trailblazer/reform) than the standard Rails architecture(s) (which are somewhat tangled and weird for nested associations), I _believe_ it should Just Work (tm). Use it how you would with AR associations, and it should work for our nested AttrJson::Models too.

You shouldn't have to use the `AttrJson::NestedAttributes` module anywhere. You will have to do a lot more work yourself, as the nature of reform.

I have not tested or experimented extensively with reform+attr_json myself, feedback welcome.
