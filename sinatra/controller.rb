require 'net/ldap'
require 'digest/md5'
require "sinatra"
require "sinatra/config_file"
require "mysql"
require "ostruct"

config_file './config/conf.yaml'

enable :sessions

configure do
  Globals = OpenStruct.new(
    :username => ''
  )
end

def validateTicket(service,ticket)
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


def requeteSql(sql)
	begin
		dbh = Mysql.real_connect(settings.database['host'],settings.database['user'], settings.database['password'],settings.database['database'])
   		@test= dbh.query(sql)
	rescue Mysql::Error => e
     		@erreur = " Error code: #{e.errno}"
     		@erreur += " Error message: #{e.error}"
     		@erreur += " Error SQLSTATE: #{e.sqlstate}" if e.respond_to?("sqlstate")
		"#{@erreur}"
   	ensure
     		dbh.close if dbh
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

get "/login" do
	
	if (params[:service])
		session[:service]=params[:service]
	end
	if (session[:username])
		@digest = Digest::MD5.hexdigest(session[:username])
		session[:tgt]='TGC-'+@digest
		Globals.username=session[:username] 
	end
	if (session[:flash])
                @flash = session[:flash]
        end
	#@debug = settings.ldap['server']
	if (params[:service] && session[:username]) 
	#fabriquer les tickets CAS puis rediriger vers service+ST
		@flash += " service "+params[:service]+" requested "
		@time = DateTime.now.to_s
		@ticket = 'ST-'+Digest::MD5.hexdigest(session[:username]+'-'+@time)
		
		@service=params[:service]
		@username=session[:username]
		Globals.username=session[:username]
		@sql="INSERT INTO casmrt_st (ticket, service, created_on, consumed, client_hostname, username, type, granted_by_pgt_id, granted_by_tgt_id ) VALUES ('#{@ticket}','"+@service+"','"+@time+"',NULL,'localhost','"+@username+"','ST',NULL,NULL);"
		@flash += @sql
		begin
			dbh = Mysql.real_connect(settings.database['host'],settings.database['user'], settings.database['password'],settings.database['database'])
			dbh.query(@sql)
			redirect @service+'?ticket='+@ticket

   		rescue Mysql::Error => e
     			@erreur = " Error code: #{e.errno}"
     			@erreur += " Error message: #{e.error}"
     			@erreur += " Error SQLSTATE: #{e.sqlstate}" if e.respond_to?("sqlstate")
			@flash += @erreur
   		ensure
     			# disconnect from server
     			dbh.close if dbh
   		end
	end
  	
	erb :login
end

get "/logout" do
	session[:code]=""
	session[:username]=nil
	session[:service]=""
	Globals.username=""
    	session[:flash]='logout successfull'
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


post "/login" do

  @username= params[:username]
  @password= params[:password]

  @dn = "uid=#{@username},ou=People,"+settings.ldap['base']
  @ldap = Net::LDAP.new(:host=>settings.ldap['server'],:port=>settings.ldap['port'],:base=>settings.ldap['base'])
  @ldap.authenticate(@dn,@password)
  @r = @ldap.bind
  if  (@r)
        @digest = Digest::MD5.hexdigest(@username)
  	session[:code] = @digest
  	session[:username] = @username
    	Globals.username=@username

	session[:flash] = 'authentication succeeded'
	if (session[:service])
                redirect session[:service]
        else
                redirect '/login'
	end
  else
    	session[:flash]='authentication failed'
	redirect '/login'
  end
end

