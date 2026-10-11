json.meta do
  json.count @calls_count
  json.current_page @calls.current_page
  json.total_pages @calls.total_pages
  json.counts @segment_counts
end

json.payload do
  json.array! @calls do |call|
    json.partial! 'api/v1/models/call', formats: [:json], call: call, handoff_variables: @handoff_variables
  end
end
