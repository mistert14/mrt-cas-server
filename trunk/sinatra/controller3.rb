require 'net/ldap'
require 'digest/md5'
require "sinatra"
require "sinatra/config_file"
require "mysql"
require "ostruct"
require 'sinatra/base'
require 'webrick'
require 'webrick/https'
require 'openssl'
require 'data_mapper'


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
    :mysql_host=>settings.database['host']
  )
end


DataMapper.setup(:default, {
    :adapter  => 'mysql',
    :database => Globals.mysql_database,
    :username => Globals.mysql_username,
    :password => Globals.mysql_password,
    :host     => Globals.mysql_host
  })


class Ticket

    include DataMapper::Resource
    property :id, Serial, :required => true
    property :ticket, String, :required => true
    property :service, Text, :required => true
    property :created_on, DateTime, :required => true
    property :consumed, DateTime
    property :client_hostname, String, :required => true
    property :username, String, :required => true
    property :type, String, :required => true
    property :granted_by_pgt_id, Integer
    property :granted_by_tgt_id, Integer

end

DataMapper.finalize
Ticket.auto_upgrade!

def validateTicket(service,ticket)
	@test = Ticket.first( :ticket => ticket, :service => service)
        if (@test)
		@test.consumed = DateTime.now().to_s
		@test.save()
		
		return true
	end
	return false
end


def validateTicket2(service,ticket)
	@ticket=ticket
	@service=service
	@sql="SELECT id FROM casmrt_st  WHERE ticket='"+@ticket+"' and service='"+@service+"' and consumed is NULL"
	#"#{@sql}"
	@test=requeteSql(@sql)
	@id=@test.fetch_row
	if (@id)
		@time=DateTime.now.to_s
		@sql2="UPDATE casmrt_st  SET consumed='"+@time+"' WHERE id='"+@id[0]+"' LIMIT 1 "
		#"#{@sql2}"
		@test2=requeteSql(@sql2)
		return true
	end
	return false
	
end



class MyServer  < Sinatra::Base



	get "/debug" do
		@test = Ticket.new()
		@test.ticket='toto'
		@test.service='toto'
		@test.username='toto'
		@test.client_hostname='localhost'
		@test.created_on=DateTime.now().to_s
		@test.type='ST'
		@test.save()
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

  			@dn = "uid=#{@username},ou=People,"+Globals.ldap_base
  			@ldap = Net::LDAP.new(:host=>Globals.ldap_server,:port=>Globals.ldap_port,:base=>Globals.ldap_base)
  			@ldap.authenticate(@dn,@password)
  			@r = @ldap.bind
			if  (@r)
				Globals.username=@username
				@digest = Digest::MD5.hexdigest(@username)
				session[:code] = @digest
				Globals.flash = 'authentication succeeded'
				if (Globals.service)
                			redirect Globals.service
        			else
                			redirect '/login'
				end
  			else
    				Globals.flash='authentication failed'
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
        :Logger             => WEBrick::Log::new($stderr, WEBrick::Log::DEBUG),
        :DocumentRoot       => "/root/sinatra",
        :SSLEnable          => true,
        :SSLVerifyClient    => OpenSSL::SSL::VERIFY_NONE,
        :SSLCertificate     => OpenSSL::X509::Certificate.new(  File.open(File.join(CERT_PATH, "server.crt")).read),
        :SSLPrivateKey      => OpenSSL::PKey::RSA.new(          File.open(File.join(CERT_PATH, "server.key")).read),
        :SSLCertName        => [ [ "CN",WEBrick::Utils::getservername ] ],
	:app                => MyServer
}




Rack::Handler::WEBrick.run MyServer, webrick_options
