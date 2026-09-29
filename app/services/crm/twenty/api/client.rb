# GraphQL client for one Twenty workspace (verified against v2.41).
#
# GraphQL rather than REST because every lookup here is a small OR over email
# and phone spellings, which variables keep out of Twenty's filter-string
# grammar, and because a person, their company and its opportunities come back
# in one request. That matters: Twenty rate-limits API keys per workspace
# (100 requests a minute, shared with every other integration on it), and it
# counts root fields, not nested relations.
class Crm::Twenty::Api::Client
  class ApiError < StandardError
    attr_reader :code

    def initialize(message, code = nil)
      @code = code
      super(message)
    end
  end

  class RateLimitError < ApiError; end

  TIMEOUT = 10

  # Hosts that only resolve inside a private network. The URL is typed by an
  # account admin and decides where a request carrying the API key goes.
  PRIVATE_HOST = /(\A|\.)(local|localhost|internal|intranet|lan|home|corp|arpa|svc|cluster\.local|test|invalid|example)\z/i

  # Twenty Cloud serves the API from one host and each workspace's app from its
  # own subdomain, which the API key does not reveal; record links only work
  # for self-hosted workspaces, where both share an origin.
  CLOUD_API_HOST = 'api.twenty.com'.freeze

  PERSON_SCALARS = <<~GRAPHQL.freeze
    id
    name { firstName lastName }
    emails { primaryEmail additionalEmails }
    phones { primaryPhoneNumber primaryPhoneCountryCode primaryPhoneCallingCode additionalPhones }
    jobTitle
    city
    linkedinLink { primaryLinkUrl }
  GRAPHQL

  COMPANY_FIELDS = 'id name domainName { primaryLinkUrl }'.freeze
  PERSON_FIELDS = "#{PERSON_SCALARS} company { #{COMPANY_FIELDS} }".freeze

  OPPORTUNITY_FIELDS = 'id name stage closeDate updatedAt amount { amountMicros currencyCode } owner { name { firstName lastName } }'.freeze

  # Nested connections ignore first/orderBy in v2.41, so they come back whole
  # and are sorted by the caller. A one-to-many two levels down (person →
  # company → opportunities) comes back empty, so the company's opportunities
  # are a query of their own.
  PERSON_CARD_QUERY = <<~GRAPHQL.freeze
    query PersonCard($id: UUID!) {
      person(filter: { id: { eq: $id } }) {
        #{PERSON_SCALARS}
        company { #{COMPANY_FIELDS} }
        pointOfContactForOpportunities { edges { node { #{OPPORTUNITY_FIELDS} } } }
        noteTargets { totalCount edges { node { note { id title createdAt bodyV2 { markdown } createdBy { name } } } } }
      }
    }
  GRAPHQL

  attr_reader :origin

  def self.valid_origin?(url)
    uri = URI.parse(url.to_s.strip.chomp('/'))
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.path.blank? && uri.userinfo.nil? &&
      !uri.host.match?(PRIVATE_HOST) && !ip_address?(uri.host)
  rescue URI::InvalidURIError
    false
  end

  def self.ip_address?(host)
    IPAddr.new(host.delete('[]'))
    true
  rescue IPAddr::InvalidAddressError
    false
  end

  def initialize(api_url:, api_key:)
    raise ApiError, 'Twenty URL must be a public https address' unless self.class.valid_origin?(api_url)

    @origin = api_url.to_s.strip.chomp('/').downcase
    @api_key = api_key
  end

  # Raises unless the key can read the workspace.
  def verify!
    query('query Verify { workspaceMembers(first: 1) { totalCount } }')
  end

  def find_people(emails:, phones:)
    conditions = emails.map { |email| { emails: { primaryEmail: { eq: email } } } }
    conditions << { phones: { primaryPhoneNumber: { in: phones } } } if phones.any?
    return [] if conditions.empty?

    data = query(<<~GRAPHQL, filter: { or: conditions })
      query FindPeople($filter: PersonFilterInput) {
        people(filter: $filter, first: 5) { edges { node { #{PERSON_FIELDS} } } }
      }
    GRAPHQL
    nodes(data['people'])
  end

  def person(id)
    query(<<~GRAPHQL, id: id)['person']
      query Person($id: UUID!) { person(filter: { id: { eq: $id } }) { #{PERSON_FIELDS} } }
    GRAPHQL
  end

  # The person with their company's latest opportunities under
  # company.opportunities, as if Twenty had nested them.
  def person_card(id, opportunity_limit: 5)
    person = query(PERSON_CARD_QUERY, id: id)['person']
    return person if person.nil? || person['company'].blank?

    person['company']['opportunities'] = query(<<~GRAPHQL, id: person['company']['id'], first: opportunity_limit)['opportunities']
      query CompanyOpportunities($id: UUID!, $first: Int) {
        opportunities(filter: { companyId: { eq: $id } }, first: $first, orderBy: [{ updatedAt: DescNullsLast }]) {
          edges { node { #{OPPORTUNITY_FIELDS} } }
        }
      }
    GRAPHQL
    person
  end

  def create_person(data)
    query(<<~GRAPHQL, data: data)['createPerson']
      mutation CreatePerson($data: PersonCreateInput!) { createPerson(data: $data) { #{PERSON_FIELDS} } }
    GRAPHQL
  end

  def update_person(id, data)
    query(<<~GRAPHQL, id: id, data: data)['updatePerson']
      mutation UpdatePerson($id: UUID!, $data: PersonUpdateInput!) { updatePerson(id: $id, data: $data) { #{PERSON_FIELDS} } }
    GRAPHQL
  end

  def find_company_id(name)
    # ilike without wildcards is a case-insensitive equals, once % and _ are escaped.
    data = query(<<~GRAPHQL, name: name.gsub(/[\\%_]/) { |char| "\\#{char}" })
      query FindCompany($name: String) { companies(filter: { name: { ilike: $name } }, first: 2) { edges { node { id } } } }
    GRAPHQL
    matches = nodes(data['companies'])
    matches.first['id'] if matches.one?
  end

  def create_company(name)
    query(<<~GRAPHQL, data: { name: name })['createCompany']
      mutation CreateCompany($data: CompanyCreateInput!) { createCompany(data: $data) { id name } }
    GRAPHQL
  end

  # The note and its link to the person go in one request: GraphQL runs
  # mutations in order, so the note exists by the time the target refers to it.
  def create_person_note(person_id:, title:, markdown:, created_by:)
    note_id = SecureRandom.uuid
    note = note_data(title, markdown).merge(id: note_id, createdBy: created_by)
    query(<<~GRAPHQL, note: note, target: { noteId: note_id, targetPersonId: person_id })
      mutation CreatePersonNote($note: NoteCreateInput!, $target: NoteTargetCreateInput!) {
        createNote(data: $note) { id }
        createNoteTarget(data: $target) { id }
      }
    GRAPHQL
    note_id
  end

  def update_note(id, title:, markdown:)
    query(<<~GRAPHQL, id: id, data: note_data(title, markdown))
      mutation UpdateNote($id: UUID!, $data: NoteUpdateInput!) { updateNote(id: $id, data: $data) { id } }
    GRAPHQL
  end

  def delete_note(id)
    query('mutation DeleteNote($id: UUID!) { deleteNote(id: $id) { id } }', id: id)
  end

  def workspace_members
    data = query(<<~GRAPHQL)
      query Members { workspaceMembers(first: 100) { edges { node { id userEmail name { firstName lastName } } } } }
    GRAPHQL
    nodes(data['workspaceMembers'])
  end

  # { 'MEETING' => { 'label' => 'Meeting', 'color' => 'sky' }, … } from the
  # workspace's own field metadata, so renamed or custom stages read right.
  def opportunity_stages
    data = request('/metadata', 'query Objects { objects(paging: { first: 200 }) { edges { node { nameSingular fieldsList { name options } } } } }')
    opportunity = nodes(data['objects']).find { |object| object['nameSingular'] == 'opportunity' }
    stage = opportunity&.dig('fieldsList')&.find { |field| field['name'] == 'stage' }
    Array(stage&.dig('options')).to_h { |option| [option['value'], option.slice('label', 'color')] }
  end

  def record_url(object, id)
    return if id.blank? || URI.parse(origin).host == CLOUD_API_HOST

    "#{origin}/object/#{object}/#{id}"
  end

  private

  def note_data(title, markdown)
    { title: title, bodyV2: { markdown: markdown } }
  end

  def nodes(connection)
    Array(connection&.dig('edges')).pluck('node')
  end

  def query(document, variables = {})
    request('/graphql', document, variables)
  end

  def request(path, document, variables = {})
    response = HTTParty.post(
      "#{origin}#{path}",
      headers: { 'Authorization' => "Bearer #{@api_key}", 'Content-Type' => 'application/json' },
      body: { query: document, variables: variables }.to_json,
      timeout: TIMEOUT
    )
    handle_response(response)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
    raise ApiError, "Twenty unreachable: #{e.message}"
  end

  def handle_response(response)
    raise RateLimitError.new('Twenty rate limit reached', 429) if response.code == 429
    raise ApiError.new("Twenty API error: #{response.code}", response.code) unless response.success?

    body = response.parsed_response
    raise ApiError.new('Twenty returned a non-JSON response', response.code) unless body.is_a?(Hash)

    errors = Array(body['errors'])
    return body['data'] if errors.empty?

    message = errors.pluck('message').join('; ')
    # Twenty reports its throttle through GraphQL as a BAD_USER_INPUT error.
    raise RateLimitError.new(message, 429) if message.start_with?('Limit reached')

    raise ApiError.new("Twenty API error: #{message}", response.code)
  end
end
