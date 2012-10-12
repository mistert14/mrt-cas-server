require 'net/ldap'
require 'digest/md5'
require "sinatra"
require "sinatra/config_file"
require "ostruct"
require 'sinatra/base'
require 'webrick'
require 'webrick/https'
require 'openssl'
require 'data_mapper'
require 'logger'
require 'models/tickets'

logger = Logger.new('log/sinatra.log')
use Rack::CommonLogger, logger

logger.level  = Logger::INFO 
logger.info "CAS service started"

enable :sessions

config_file '/root/sinatra/config/conf.yaml'


configure do
  enable :logging
  Globals = OpenStruct.new(
    :service => '',
    :flash => '',
    :username => '',
    :network_port=>settings.network['port'],
    :ldap_port=>settings.ldap['port'],
    :ldap_base=>settings.ldap['base'],
    :ldap_server=>settings.ldap['server'],
    :mysql_database=>settings.database['database'],
    :mysql_username=>settings.database['username'],
    :mysql_password=>settings.database['password'],
    :mysql_host=>settings.database['host'],
    :logger=>logger
  )
end


def validateTicket(service,ticket)
	@test = Ticket.first( :ticket => ticket, :service => service)
        if (@test)
		@test.consumed = DateTime.now().to_s
		@test.save()
		Globals.logger.level  = Logger::INFO 
		Globals.logger.info "Ticket #{@test.ticket} was validated for service #{@test.service} for user #{@test.username}"
		
		return true
	end
	return false
end

class MyServer  < Sinatra::Base


	get "/log" do
		begin
  	    		file = File.new("./log/sinatra.log", "r")
  			counter = 0
			tmp =""
			while (line = file.gets)
  				tmp +="#{line}"+"<br />"
  				counter = counter + 1
  			end
  			file.close
			"
			#{tmp}
			"
  		rescue => err
  			"Exception: #{err}"
  			
  		end

	end

	get "/debug" do
	end

	get "/" do
		if (session[:username])
                	Globals.username=session[:username]
		end
		redirect '/login'
	end
	post "/login" do

		begin
  			@username= params[:username]
  			@password= params[:password]

			Globals.logger.level  = Logger::INFO 
			Globals.logger.info "Login request"


  			@dn = "uid=#{@username},ou=People,"+Globals.ldap_base
  			@ldap = Net::LDAP.new(:host=>Globals.ldap_server,:port=>Globals.ldap_port,:base=>Globals.ldap_base)
  			@ldap.authenticate(@dn,@password)
  			@r = @ldap.bind
			if  (@r)
				Globals.username=@username
				@digest = Digest::MD5.hexdigest(@username)
				session[:code] = @digest
				Globals.flash = 'authentication succeeded'
				Globals.logger.info "authentication succeeded for user #{@username}"
				if (Globals.service)
                			redirect Globals.service
        			else
                			redirect '/login'
				end
  			else
    				Globals.flash='authentication failed'
    				Globals.loger.info="authentication failed for user #{@username}"
				redirect '/login'
  			end
		rescue
			"FATAL ERROR"
		end
	end

	get "/login" do
		
		if (params[:service])
			Globals.service=params[:service]
		end
		if (Globals.username)
			@digest = Digest::MD5.hexdigest(Globals.username)
			session[:tgt]='TGC-'+@digest
		end
		if (Globals.flash)
                	@flash = Globals.flash
        	end
		if (params[:service] && Globals.username) 
			#fabriquer les tickets CAS puis rediriger vers service+ST
			@flash += " service "+params[:service]+" requested "
			@time = DateTime.now.to_s
			@ticket = 'ST-'+Digest::MD5.hexdigest(Globals.username+'-'+@time)
		
			@service=params[:service]
			Globals.service=params[:service]
			@username=Globals.username
			Globals.logger.info "Ticket #{@ticket} emitted for service #{@service} and user #{@username}, will redirect"	
				@test = Ticket.new()
				@test.ticket=@ticket
				@test.service=@service
				@test.username=@username
				@test.client_hostname='localhost'
				@test.created_on=DateTime.now().to_s
				@test.type='ST'
				@test.save()

				redirect @service+'?ticket='+@ticket

		end
		erb :login
	end

	get "/logout" do
		Globals.logger.info "Logout request for user #{Globals.username}"	
		session[:code]=""
		Globals.service=""
		Globals.username=nil
    		Globals.flash='logout successfull'
		redirect '/login'
	end

	get "/validate" do
		@username=Globals.username
		if (!@username)
			redirect '/login'
		end
		@ticket=params[:ticket]
		@service=params[:service]
		content_type 'text/plain'
		if (validateTicket(@service,@ticket))
			erb :simpleResponse
		else
			erb :simpleNoResponse 
		end	
	
	end

	get "/serviceValidate" do
		@username=Globals.username
		if (!@username)
			redirect '/login'
		end
		@ticket=params[:ticket]
		@service=params[:service]
		content_type 'text/xml'
		if (validateTicket(@service,@ticket))
			erb :casResponse
		else
			erb :casNoResponse
		end	
	end

	get "/proxyValidate" do
		@username=Globals.username
		if (!@username)
			redirect '/login'
		end

		content_type 'text/xml'
		@ticket=params[:ticket]
		@service=params[:service]
		content_type 'text/xml'
		if (validateTicket(@service,@ticket))
			erb :proxyResponse
		else
			erb :proxyNoResponse
		end	
	end



end

CERT_PATH = '/root/sinatra/'


webrick_options = {
        :Port               => 443,
        #:Logger             => WEBrick::Log::new($stderr, WEBrick::Log::DEBUG),
        :DocumentRoot       => "/root/sinatra",
        :SSLEnable          => true,
        :SSLVerifyClient    => OpenSSL::SSL::VERIFY_NONE,
        :SSLCertificate     => OpenSSL::X509::Certificate.new(  File.open(File.join(CERT_PATH, "server.crt")).read),
        :SSLPrivateKey      => OpenSSL::PKey::RSA.new(          File.open(File.join(CERT_PATH, "server.key")).read),
        :SSLCertName        => [ [ "CN",WEBrick::Utils::getservername ] ],
	:app                => MyServer
}




Rack::Handler::WEBrick.run MyServer, webrick_options
