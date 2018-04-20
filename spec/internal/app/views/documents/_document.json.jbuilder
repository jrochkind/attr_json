json.extract! document, :id, :title, :json_attributes, :created_at, :updated_at
json.url document_url(document, format: :json)
