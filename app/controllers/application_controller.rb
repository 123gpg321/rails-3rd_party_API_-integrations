class ApplicationController < ActionController::Base
    rescue_from StandardError, :with => :rescue_unknown_exceptions

    def rescue_unknown_exceptions
      log_stacktrace
      setup
      support_ticket=SupportTickets.new(:env => @_env,
                                        :admin => @admin,
                                        :login => @login,
                                        :slack_channel => @slack_channel,
                                        :ari => @ari,
                                        :auto_tickets_create=>@auto_tickets_create)
      
      @ticket, @access_is, @ticket_exists=support_ticket.create
      
      slack=SlackApiIntegration.new(:slack_channel=>@slack_channel)
      slack.notify
      render_json
    end

  end

end
