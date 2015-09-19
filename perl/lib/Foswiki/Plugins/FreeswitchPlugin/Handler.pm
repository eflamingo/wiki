package Foswiki::Plugins::FreeswitchPlugin::Handler;

use strict;
use warnings;


use Assert;
use DBI;
use  Foswiki::Plugins::FreeswitchPlugin::User();
use Foswiki::Plugins::FreeswitchPlugin::Domain();
use Foswiki::Plugins::FreeswitchPlugin::Gateway();
use Foswiki::Contrib::DBIStoreContrib::Handler();

# list all of the tables
my $pgsqlnamespace = "freeswitch";
my $handlerTables = { Domains => qq/$pgsqlnamespace."Domains"/,Groups => qq/$pgsqlnamespace."Groups"/,Users => qq/$pgsqlnamespace."Users"/,
	DialPlan => qq/$pgsqlnamespace."DialPlan_Lookups"/, DialPlanToDomain => qq/$pgsqlnamespace."DialPlanToDomain"/, DialPlan_Finder => qq/$pgsqlnamespace."DialPlan_KeyFinder"/,
	Call_History => qq/$pgsqlnamespace."Call_History"/, Topics => qq/foswiki."Topics"/, Sites => qq/foswiki."Sites"/, DiD_Inventory => qq/accounts."DiD_Inventory"/,
	MetaPreferences => qq/foswiki."MetaPreferences_History"/, FusionNumbers => qq/freeswitch."Fusion_Numbers"/
};


sub _getTable {
	my $table_name = shift;
	return $handlerTables->{$table_name};
}
# handler->getTable('blah')
sub getTable {
	my $this = shift;
	my $table_name = shift;
	return $handlerTables->{$table_name};
}


# confusing, this comes from DBIStore
sub getTableName {
	my $this = shift;
	my $table_name = shift;
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	return $Foswiki::Contrib::DBIStoreContrib::Handler::handlerTables->{$table_name};
}

# Caching
my $freeswitch_cache;

# domain, login_name => returns u1.user_key, u1."password", u1.email, u1.preferences
sub fetchUserRow {
	my $this = shift;
	my ($domain,$user_id) = @_;
	my @fields = ('user_key','password','email','preferences');
	my $bool = 1;
	foreach my $x (@fields){
		$bool = 0 unless $freeswitch_cache->{$domain}->{$user_id}->{$x};
	}
	return $freeswitch_cache->{$domain}->{$user_id} if $bool;
	return undef; 
}
# puts a user row in
sub putUserRow {
	my $this = shift;
	my $domain = shift;
	my $user_id = shift;
	my $user_row = shift;
	
	my @fields = ('user_key','password','email','preferences');
	my $bool = 1;
	foreach my $x (@fields){
		$bool = 0 unless $user_row->{$x};
	}
	$freeswitch_cache->{$domain}->{$user_id} = $user_row if $bool;
	return $freeswitch_cache->{$domain}->{$user_id};
}


###########################   General Purpose Start Up Procedure   #################################
# DomainHandler::->new($domain_name)->$responsexml for domain section
sub new {
	my $class = shift;
	my $session = shift;
	my $this;
	 
	$this->{session} = $session;
	bless $this,$class;
	$this->_startNewdbiconnection();
	return $this;
}


# create a connection to the database
sub _startNewdbiconnection {
	my $this = shift;
	# Steal the database connection from DBIStoreContrib
	$this->{site_handler} = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $dbconnection = $this->{site_handler}->database_connection();	
	$dbconnection->{AutoCommit} = 1;  # disable transactions
	return $dbconnection;
}

# database connection
sub database_connection {
	my $this = shift;
	return $this->{site_handler}->database_connection();
}

sub DESTROY {
	my $this = shift;
	$this->finish();
}

sub finish {
    my $this = shift;
	undef $this->{site_handler};
}

# This rolls back any ongoing transactions before the connection is closed
sub cleanUpSQL {
	my $this = shift;
	$this->database_connection()->rollback;
}



# ($domain_name, Domain::->new($domain_name))-> add to cache
sub addDomain {
	my $this = shift;
	my ($domain_name,$domain_obj) = @_;
	$this->{domains}->{$domain_name} = $domain_obj;
}

sub addGateway {
	my $this = shift;
	my ($gatewayname,$gateway_obj) = @_;
	$this->{gateways}->{$gatewayname} = $gateway_obj;
}
##########################    Database Interaction    #################################
# fetch one domain
sub getOneDomain {
	my $this = shift;
	my $domain_name = shift;
	my $domain_obj = Foswiki::Plugins::FreeswitchPlugin::Domain::->new($domain_name,$this);
	$this->addDomain($domain_name,$domain_obj) if $domain_obj->context;
}

# fetch all of the domains
sub fetch_domains {
	my $this = shift;
	my $Domains = _getTable('Domains');
	my $selectStatement = qq/SELECT d1.site_key, d1.local_preferences, d1.default_preferences, d1.domain_name FROM $Domains d1; /;
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute();
	my ($site_key,$localp,$defaultp,$domain_name);
	$selectHandler->bind_col( 1, \$site_key );
	$selectHandler->bind_col( 2, \$localp );
	$selectHandler->bind_col( 3, \$defaultp );
	$selectHandler->bind_col( 4, \$domain_name );

	while ($selectHandler->fetch) {
		my $domain_obj = Foswiki::Plugins::FreeswitchPlugin::Domain::->new($domain_name,$this);
		$this->addDomain($domain_name,$domain_obj) if $domain_obj->context;
	}
	
	# load the groups
	$this->_load_groups();
	# load prefs from Local and Default Site Preferences
	return $this->{domains};
}

sub fetch_gateways {
	my $this = shift;

	$this->fetch_fusion_users;
	$this->fetch_agile_ne_jp;
	$this->fetch_icall;
	return $this->{gateways};
}
# fetch agile (which is just handwritten xml)
sub fetch_agile_ne_jp {
	my $this = shift;
	my $gateway_obj = Foswiki::Plugins::FreeswitchPlugin::Gateway::->new('agile_ne_jp');
	$gateway_obj->type('agile_ne_jp');
	$gateway_obj->set_parameters();
	$this->addGateway($gateway_obj->xmlname,$gateway_obj);
	return $this->{gateways};
}

# fetch icall_international and icall_domestic (which is just handwritten xml)
sub fetch_icall {
	my $this = shift;
	my $gateway_obj_local = Foswiki::Plugins::FreeswitchPlugin::Gateway::->new('icall_domestic');
	$gateway_obj_local->type('icall_domestic');
	$gateway_obj_local->set_parameters();
	$this->addGateway($gateway_obj_local->xmlname,$gateway_obj_local);
	
	my $gateway_obj_int = Foswiki::Plugins::FreeswitchPlugin::Gateway::->new('icall_international');
	$gateway_obj_int->type('icall_international');
	$gateway_obj_int->set_parameters();
	$this->addGateway($gateway_obj_int->xmlname,$gateway_obj_int);
	
	
	return $this->{gateways};
}

# fetch all of the user/numbers from the fusion table, register them as gateways
sub fetch_fusion_users {
	my $this = shift;
	my $Fun = _getTable('FusionNumbers');
	my $selectStatement = qq/SELECT fun.full_number, fun.id, fun.password FROM $Fun fun; /;
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute();
	my ($full_number,$id,$password);
	$selectHandler->bind_col( 1, \$full_number );
	$selectHandler->bind_col( 2, \$id );
	$selectHandler->bind_col( 3, \$password );
	my @gatewayArray;
	while ($selectHandler->fetch) {
		# the "new" function's arguement sets the xmlname variable
		my $gateway_obj = Foswiki::Plugins::FreeswitchPlugin::Gateway::->new('fusion_'.$id);
		
		$gateway_obj->full_number($full_number);
		$gateway_obj->username($id);
		$gateway_obj->password($password);
		$gateway_obj->type('fusion');
		$gateway_obj->set_parameters();
		$this->addGateway($gateway_obj->xmlname,$gateway_obj);
	}
	return $this->{gateways};
}

sub _load_groups {
	my $this = shift;
	my $dbconnection = $this->database_connection();
	
	my $Users = _getTable('Users');
	my $Groups = _getTable('Groups');
	
	# get the groups
	my $selectStatement = qq/SELECT g1."domain", g1.group_key, g1.members FROM $Groups g1;/;

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute();
	my ($domain,$group_key,$members);
	$selectHandler->bind_col( 1, \$domain );
	$selectHandler->bind_col( 2, \$group_key );
	$selectHandler->bind_col( 3, \$members );
	while ($selectHandler->fetch) {
		my $domain_obj = $this->{domains}->{$domain};
		next unless $domain_obj;
		# somehow split up $members
		
		my @memberDumb = ($members =~ m/\{(.*?)\}/g);
		my $members = $memberDumb[0];
		my @all_memb = split(',',$members);
		# stuff it into the Domain Object
		$domain_obj->setGroup($group_key,\@all_memb);
	}
}
# ($domain,$user_id)->xml for user
sub fetchUser {
	my $this = shift;
	# the options is for the MailToWikiPlugin
	my ($domain_name,$user_id,$options) = @_;
	my $domain_obj;
	my $context;
	if($this->{domains}->{$domain_name}){
		$domain_obj = $this->{domains}->{$domain_name};
	}
	else{
		$domain_obj = Foswiki::Plugins::FreeswitchPlugin::Domain::->new($domain_name,$this);
		$this->addDomain($domain_name,$domain_obj);
	}
	$context = $domain_obj->context;
	$domain_obj->_getDialPlanKeyByDomain() unless $context;
	$context = $domain_obj->context;
	die "No Context" unless $context || $options->{'nocontext'} == 1;
	
	# check if the user is in the cache already
	my $user_row = $this->fetchUserRow($domain_name,$user_id);
	if(!$user_row){
		my $Users = _getTable('Users');
		my $selectStatement = qq/SELECT u1.user_key, u1."password", u1.email, u1.preferences 
FROM 
  $Users u1
WHERE
  u1."domain" = ? AND u1.login_name = ?;/; # 1-domain, 2-login_name 
		my $selectHandler = $this->database_connection()->prepare($selectStatement);
		$selectHandler->execute($domain_name,$user_id);
		my ($user_key,$passwdE,$email,$preferences);
		$selectHandler->bind_col( 1, \$user_key );
		$selectHandler->bind_col( 2, \$passwdE );
		$selectHandler->bind_col( 3, \$email );
		$selectHandler->bind_col( 4, \$preferences );
		while ($selectHandler->fetch) {
			# load the user cache
			$user_row->{'user_key'} = $user_key;
			$user_row->{'password'} = $passwdE;
			$user_row->{'email'} = $email;
			$user_row->{'preferences'} = $preferences;
			$this->putUserRow($domain_name,$user_id,$user_row);
		}
	}
	my $user_obj = Foswiki::Plugins::FreeswitchPlugin::User::->new($user_id);
	# <variable name="effective_caller_id_name" value="Extension 3001"/>
	$user_obj->setVariable('effective_caller_id_name','Extension 0000');
	# <variable name="effective_caller_id_number" value="3001"/>
	$user_obj->setVariable('effective_caller_id_number','0000');
	# <variable name="outbound_caller_id_name" value="$${outbound_caller_name}"/>
	$user_obj->setVariable('outbound_caller_id_name','$${outbound_caller_name}');
	# <variable name="outbound_caller_id_number" value="$${outbound_caller_id}"/>
	$user_obj->setVariable('outbound_caller_id_number','$${outbound_caller_id}');
	# <variable name="user_context" value="some-guid-in-hex-form"/>
	#$user_obj->setVariable('user_context',$context);
	
		
	# <param name="email-addr" value="dejesus.joel@gmail.com"/>
	$user_obj->setParameter('email-addr',$user_row->{'email'});
    # <param name="a1-hash" value="50046ba744759aa83e045ba0b996e7a9"/>
    $user_obj->setParameter('a1-hash',$user_row->{'password'});
    # <param name="vm-delete-file" value="true"/>
    $user_obj->setParameter('vm-delete-file','true');
	# <param name="vm-attach-file" value="true"/>
	$user_obj->setParameter('vm-attach-file','true');
	# <param name="vm-mailto" value="brian@yourdomain.com"/>
	$user_obj->setParameter('vm-mailto',$user_row->{'email'});
	# <param name="vm-mailfrom" value="noreply@yourdomain.com"/>
	$user_obj->setParameter('vm-mailfrom','noreply@'.$domain_name);
	# <param name="vm-email-all-messages" value="true"/>
	$user_obj->setParameter('vm-email-all-messages','true');
	# add the user to the domain
	$domain_obj->addUser($user_obj);
	
	return $user_row;
}



sub _load_site_prefs {
	my $this = shift;
	my $dbconnection = $this->database_connection();
}

sub print_directory {
	my $this = shift;
	my $return_xml = '';
	my @domain_names = keys %{$this->{domains}};
	foreach my $domain (@domain_names){
		$return_xml .= $this->{domains}->{$domain}->print_domain();
	}
	$return_xml = '<document type="freeswitch/xml"><section name="directory">'.$return_xml.'</section></document>';
  
	return $return_xml;
}

####### Extenions and DialPlans #########
sub getExtension {
	my $this = shift;
	my $input_ref = shift;
	my $dial_plan_key = $input_ref->{'dial_plan_key'};
	my $dest_num = $input_ref->{'destination_number'};
	my $from_ip = $input_ref->{'variable_sip_from_host'};

	require  Foswiki::Plugins::FreeswitchPlugin::Extension;
	#  EXTERNAL_DIALPLAN needed for public context	
	my $extension = Foswiki::Plugins::FreeswitchPlugin::Extension::->new($this,$dial_plan_key,$dest_num,$from_ip);
	return undef unless $extension;

	my $answer;
	$answer = $extension->printXML();
	
	return $answer;
}



1;
__END__

SELECT 
  w1.current_web_name AS web, 
  bname."value" AS topic,
  eblob."value" AS row_data
FROM 
  foswiki."Topics" t1
	INNER JOIN foswiki."EditTable_Data" etd ON t1.link_to_latest = etd.topic_history_key
	INNER JOIN foswiki."Blob_Store" bname ON t1.current_topic_name = bname."key"
	INNER JOIN foswiki."Webs" w1 ON t1.current_web_key = w1."key",
  foswiki."Sites" s1,
  foswiki."Blob_Store" eblob
WHERE

  bname."value" = 'ExternalDialPlan'
  AND w1.current_web_name = 'Main'
  AND w1.site_key = s1."key"
  AND s1.current_site_name = 'tokyo.e-flamingo.net'
  AND eblob."key" = etd.row_blob
;

