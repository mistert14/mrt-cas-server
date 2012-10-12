config_file 'config/conf.yaml'

DataMapper.setup(:default, {                                                 
    :adapter  => 'mysql',
    :database => settings.database['database'],
    :username => settings.database['username'],
    :password => settings.database['password'],
    :host     => settings.database['host'],
})


DataMapper.finalize


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

Ticket.auto_upgrade!
