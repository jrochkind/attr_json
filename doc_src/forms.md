# Use with Forms and Form builders

We've tried to make your json_attributes just as easy to work with Rails form builders as ordinary attributes, including treating nested/compound models as if they were Rails associations in forms.

It's worked out pretty well. This is one of the more complex parts of our json_attribute code, making it work with all the Rails weirdness on nested params, multi-param attributes (generally used for dates), etc. So if a bug is gonna happen somewhere, it's probably here. But at the moment it looks pretty solid and stable.

We even integration test with [simple_form](https://github.com/plataformatec/simple_form) and [cocoon](https://github.com/nathanvda/cocoon) (see below, some custom config may be required).
You can look at our [stub app used for integration tests](../spec/internal) as an example if you like.

## Standard Rails form builder

### Simple attributes

    json_attribute :some_string, :string
    json_attribute :some_datetime, :datetime

Use with form builder just as you would anything else.

    f.text_field :some_string
    f.datetimme_field :some_datetime

It _will_ work with the weird rails multi-param setting used for date fields.

Don't forget you gotta handle strong params same as you would for any ordinary attribute.

### Arrays of simple attributes

    json_attribute :string_array, :string, array: true

The ActionView+ActiveRecord architecture isn't really setup for an array of "primitives", but you can make it work:

    <% f.object.string_array.each do |str| %>
      <%= f.text_field(:string_array, value: str, multiple: true) %>
    <% end %>

That will submit and update fine, although when you try to handle reporting validation errors, you'll probably only be able to report on the array, not the specific element.

You may want to [use SimpleForm and create a custom input](https://github.com/plataformatec/simple_form#custom-inputs) to handle arrays of primitives in the way you want. Or you may want to consider an array of JsonAttribute::Model value types instead -- you can have a model with only one attribute! It can be handled more conventionally, see below.

### Embedded JsonAttribute::Model attributes

With ordinary rails associations handled in the ordinary Rails way, you use [accepts_nested_attributes_for](http://api.rubyonrails.org/classes/ActiveRecord/NestedAttributes/ClassMethods.html) for associations (to-one or to-many).

You can handle a single or array JsonAttribute::Model json_attribute similarly, but you have to:

* include JsonAttribute::NestedAttributes in your model, and then
* use our own similar `json_attribute_accepts_nested_attributes_for` instead.  It _always_ has `allow_destroy`, and some of the other `accepts_nested_attributes_for` options also don't apply, see method for full options.

```ruby
class Event
  include JsonAttribute::Model

  json_attribute :name
  json_attribute :datetime
end
class MyRecord < ActiveRecord::Base
  include JsonAttribute::Record
  include JsonAttribute::NestedAttributes

  json_attribute :one_event, Event.to_type
  json_attribute :many_events, Event.to_type, array: true

  json_attribute_accepts_nested_attributes_for :one_event, :many_events
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

Note that the `JsonAttributes::NestedAttributes` module also adds convenient rails-style `build_` methods for you.  In the case above, you get a `build_one_event` and `build_many_event` (note singularization, cause that's how Rails does) method, which you can use much like Rails' `build_to_one_association` or `to_many_assocication.build` methods. You can turn off creation of the build methods with an option to `

### Nested multi-level/compound embedded models

A model inside a model inside a model?  Some single and some array? No problem, should just work.

Remember to add `include JsonAttribute::NestedAttributes` to all your JsonAttribute::Models (or at least non-terminal ones). Remember that Rails strong params have to be dealt with and are confusing here, but you deal with them the same way you would multi-nested associations on a rails form.

## Simple Form

One of the nice parts about [simple_form](https://github.com/plataformatec/simple_form) is how you can just give it `f.input`, and it figures out the right input for you.

JsonAttribute by default, on an ActiveRecord::Base, doesn't register it's `json_attributes` in the right way for simple_form to reflect and figure out their types. However, you can ask it to with `rails_attribute: true`.

```ruby
class SomeRecord < ActiveRecord::Base
  include JsonAttribute::Record

  json_attribute :my_date, :date, rails_attribute: true
end
```

This will use the [ActiveRecord::Base.attribute](http://api.rubyonrails.org/classes/ActiveRecord/Attributes/ClassMethods.html) method to register the attribute and type, and SimpleForm will now be able to automatically look up attribute type just as you expect. (Q: Should we make this default on?)

You don't need to do this in your nested JsonAttribute::Model classes, SimpleForm will already be able to reflect on their attribute types just fine as is.

## Cocoon

[Cocoon](https://github.com/nathanvda/cocoon) is one easy way to implement js-powered add- and remove-field functionality for to-many associations nested on a form with Rails.

It _almost_ "just works" with nested/compound JsonAttribute::Model attributes, used with rails `fields_for` form builder as above. But Cocoon is looking for some ActiveRecord-specific methods that don't exist in our JsonAttribute::Models -- although it doesn't actually matter what these methods return, Cocoon works with our architecture either way.

Include the `JsonAttribute::Model::CocoonCompat` module in your **JsonAttribute::Model** classes to get these methods so Cocoon will work.

We have an integration test running a real rails app ensuring both simple_form and cocoon continue to work.

## Reform?

If you would rather use [Reform](https://github.com/trailblazer/reform) than the standard Rails architecture(s) (which are somewhat tangled and weird for nested associations), I _believe_ it should Just Work (tm). Use it how you would with AR associations, and it should work for our nested JsonAttribute::Models too.

You shouldn't have to use the `JsonAttribute::NestedAttributes` module anywhere. You will have to do a lot more work yourself, as the nature of reform.

I have not tested or experimented extensively with reform+json_attributes myself, feedback welcome.
