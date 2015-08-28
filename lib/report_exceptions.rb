module ReportExceptions
  require 'zendesk_api'
  require "net/http"
  require "uri"
  require 'logger'

  class SupportTickets
    attr_accessor :env, :admin, :login, :slack_channel, :ari, :auto_tickets_create

    def initialize(params = {})
      @req_env = params[:env]
      @admin = params[:admin]
      @login = params[:login]
      @slack_channel = params[:slack_channel]
      @ari = params[:ari]
      @auto_tickets_create = params[:auto_tickets_create]
    end

    public

    def create
      @access_is=:admin
      if [nil, 2, 3, 4, 5, 6, 7, 8].include?(@ari)
        @access_is=:non_admin

        prepare_request

        @venue=Model.where(:login_id => @login.try(:id)).first
        contacts_id=Model.where(:login_id => @login.try(:id)).first.try(:contact_id)
        @contacts_name=Model.where(:id => contacts_id).first.try(:contact_name)

        exception_hash_request={:exception_class => "#{$!.class}",
                                :controller => @req_env['action_dispatch.request.path_parameters'][:controller].to_s}.to_s

        @exception_hash_request = Digest::SHA1.hexdigest exception_hash_request

        @reduce=Model.where(:settingKey => 'zendesk.tickets.create.reduce').first.settingValue.to_i == 1

        @ticket_exists=has_existing_ticket?

        if @auto_tickets_create and !@ticket_exists

          @enviro="DEV" if @slack_channel=="#n-example-dev"
          @enviro="SANDBOX" if @slack_channel=="#n-example-sb"
          @enviro="PRODUCTION" if @slack_channel=="#n-example-live"

          @admin_name=@admin.first_name + " " + @admin.last_name if @admin

          create_ticket
        end
      end

      return [@ticket, @access_is, @ticket_exists]
    end

    private

    def has_existing_ticket?
      ticket_exist_in_zendesk?
    end

    def ticket_exist_in_zendesk?
      existing_tickets=@client.search(query: "type:ticket fieldvalue:#{@exception_hash_request}", reload: true).fetch if @reduce
      existing_tickets=@client.search(
          query: "type:ticket requester:#{(@login.try(:email_address) or 'unknown_user@example.com')} fieldvalue:#{@exception_hash_request}",
          reload: true).fetch unless @reduce

      if existing_tickets.any?
        @ticket=existing_tickets[0]
      end

      return existing_tickets.any?
    end

    def prepare_request
      @client = ZendeskAPI::Client.new do |config|
        config.url = "https://example.zendesk.com/api/v2/"
        config.username = "name@example.com"
        config.token = "-------------------------IUF0"
        config.password = "password"
        config.retry = true
        config.cache = false
        config.logger = Logger.new(STDOUT)
      end

      @json_payload_data_id=12312312927
      @stacktrace_data_id=1231218628
      @requester_email_data_id=2123123087
      @endpoint_data_id=212312316097
      @exception_message=26123123548
      @exception_class=21231234538
      @exception_hash=2343433488
      @env=26343434357
      @controller=26454545407
      @request_method=245454545438
    end

    def create_ticket
      @ticket=@client.tickets.create(
          :subject => "A bug was reported to our tech team #{('on ' + @enviro) if @enviro != "PRODUCTION" }",
          :comment => {:body => "I experienced a problem on Example Service."},
          :priority => "urgent",
          :group_id => 24405217,
          :requester => {
              :name => "#{(@contacts_name or @venue.try(:venue_name) or @admin_name or @login.try(:email_address))}",
              :email => (@login.try(:email_address) or 'unknown_user@example.com')
          },
          :custom_fields => [{
                                 :id => @json_payload_data_id,
                                 :value => "#{@req_env['action_dispatch.request.request_parameters'].to_json}"
                             },
                             {
                                 :id => @stacktrace_data_id,
                                 :value => "#{$!.backtrace[0..19].join("\n")}"
                             },
                             {
                                 :id => @requester_email_data_id,
                                 :value => "#{(@login.try(:email_address) or 'unknown_user@example.com')}"
                             },
                             {
                                 :id => @exception_message,
                                 :value => "#{$!.message}"
                             },
                             {
                                 :id => @exception_hash,
                                 :value => @exception_hash_request
                             },
                             {
                                 :id => @exception_class,
                                 :value => "#{$!.class}"
                             },
                             {
                                 :id => @endpoint_data_id,
                                 :value => "#{@req_env['REQUEST_PATH']}"
                             },
                             {
                                 :id => @env,
                                 :value => @enviro
                             },
                             {
                                 :id => @controller,
                                 :value => @req_env['action_dispatch.request.path_parameters'][:controller].to_s
                             },
                             {
                                 :id => @request_method,
                                 :value => @req_env['REQUEST_METHOD']
                             }
          ]
      )
    end
  end

  class SlackApiIntegration

    attr_accessor :slack_channel

    def initialize(params={})
      @slack_channel=params[:slack_channel]
      @import=params[:import]
    end

    def notify
      if Settings.where(:settingKey => 'log.admin.exceptions.to.slack').first.settingValue.to_i == 1
        #Slack API Exceptions
        url = URI.parse("https://hooks.slack.com/services/----CC8PJ/B---ZQS/VDi2FoPs------------9")

        @settings_env= "http://test-dev.example.com/"

        @username="[DEV]" if @settings_env=="http://test-dev.example.com/"
        @username="[SANDBOX]" if @settings_env=="https://test-sandbox.example.com/"
        @username="[PRODUCTION]" if @settings_env=="https://test.example.com/"

        prepare_request

        req = Net::HTTP::Post.new(url.request_uri)
        req.body=@hash.to_json
        http = Net::HTTP.new(url.host, url.port)
        http.ca_file = "path/to/cacert.pem" if @username == "[PRODUCTION]"
        http.use_ssl = (url.scheme == "https")

        http.request(req)
      end
    end

    private

    def prepare_request
      for_exceptions
      for_imports
    end

    def for_exceptions
      if @slack_channel.include? '#n-exceptions'
        @hash={

            "username" => @username,
            "channel" => @slack_channel,
            "icon_emoji" => ":custom_emoji:",
            "mrkdwn" => true,
            "text" => "Exception DateTime: #{Time.now}",
            "attachments" => [
                {
                    "fallback" => "*#{$!.class} #{$!.comssage}*",
                    "pretext" => "*#{$!.class} #{$!.comssage}*",
                    "color" => "#D00000",
                    "mrkdwn_in" => ["text", "pretext", "fallback"],
                    "text" => "```#{$!.backtrace[0..49].join("\n")}```"
                }
            ]
        }
      end
    end

    def for_imports
      if @slack_channel.include? '#n-reports'
        @hash={
            "username" => @username,
            "channel" => @slack_channel,
            "icon_emoji" => ":custom_emoji:",
            "mrkdwn" => true,
            "text" => "Spreadsheet uploaded succesfuly.",
            "attachments" => [
                {
                    "title" => @import[:venue_name],
                    "title_link" => "resourcelinkexample",
                    "color" => "#D00000",
                    "mrkdwn_in" => ["text", "pretext", "fallback"],
                    "text" => "*#{@import[:spreadsheet_name]}*"
                }
            ]
        }
      end
    end
  end

  def log_stacktrace
    logger.error $!.class
    logger.error $!.message
    logger.error $!.backtrace.join("\n")
  end

  def setup
    @slack_channel=Model.where(:example => 'slack.channel.example.exception').first.settingValue
    @auto_tickets_create=Model.where(:example => 'example.zendesk.tickets.create').first.settingValue.to_i == 1
    @ari=Model.where(:login_id => @login.try(:id)).first.try(:access_role_id)
  end

  def render_json
    json ={:message => "Something broke on our server.",
           :support_ticket_id => @ticket[:id],
           :new_ticket => (@ticket_exists ? false : true)} if @auto_tickets_create == true

    json={:message => "Something broke on our server.",
          :ticket_creation => false} if @auto_tickets_create == false

    if @access_is==:non_admin
      render :status => 500, :json => json
    else
      render :status => 500, :json => {:message => "Something broke on our server."}
    end
  end

end