package Foswiki::Plugins::FreeswitchPlugin::Extension;

use strict;
use warnings;


use Assert;
use Foswiki::Plugins::FreeswitchPlugin::Handler ();


=pod
section=dialplan&tag_name=&key_name=&key_value=&context=default&destination_number=556
&caller_id_name=FreeSwitch&caller_id_number=5555551212&network_addr=&ani=&aniii=&rdnis=
&source=mod_portaudio&chan_name=PortAudio/556&uuid=b7f0b117-351f-9448-b60a-18ff91cbe183
&endpoint_disposition=ANSWER

<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<document type="freeswitch/xml">
  <section name="dialplan" description="RE Dial Plan For FreeSwitch">
    <context name="default">
      <extension name="test9">
        <condition field="destination_number" expression="^83789$">
          <action application="bridge" data="iax/guest@conference.freeswitch.org/888"/>
        </condition>
      </extension>
    </context>
  </section>
</document>

=cut
my $sip_proxy_ip = "223.219.93.171";

# new($handler,$user_key,$dest_num,$from_ip)->$extension object
sub new {
	my $class = shift;
	my $handler = shift;
	my $dial_plan_key = shift;
	my $destination_number = shift;
	my $from_ip = shift;
	my $this;
	$this->{handler} = $handler;
	
	# the topic with the edittable that defines the dialplan
	$this->{dialplan} = $dial_plan_key; # <-- derived from site preferences
	$this->{domain} = undef; # <-- derived from dialplan topic_key
	$this->{site_key} = undef; # <-- derived from dialplan topic_key
	# self_descriptive
	$this->{destination_number} = $destination_number;
	# for public numbers incoming 
	$this->{from_ip} = $from_ip;
	# the table from the database with the call actions
	$this->{extensions} = undef;
	# this is for when calls come from a public context
	$this->{transfer} = undef;
	bless $this, $class;
	my $bool = 0;
	
	# external
	if( $dial_plan_key eq 'public' || !$dial_plan_key){
		# transfer the call to the proper context
		my $tx_dial_plan_key = $this->_getPublicDialPlan();
		$bool = 1 if $tx_dial_plan_key;
		$this->_loadTransfer($tx_dial_plan_key);
	}
	else{
		# if the dial plan key is an INTERNAL DIALPLAN from a website
		$bool = $this->_loadContext();
		return undef unless $bool;
		$bool = 0;
		$this->_loadExtensions();	
	}
	

	
	return $this;
}

sub destination_number {
	my $this = shift;
	my $table = shift;
	if($table){
		$this->{destination_number} = $table;
		return $this->{destination_number};
	}
	else{
		return $this->{destination_number};
	}
}
sub domain {
	my $this = shift;
	my $table = shift;
	if($table){
		$this->{domain} = $table;
		return $this->{domain};
	}
	else{
		return $this->{domain};
	}
}
sub dialplan {
	my $this = shift;
	my $table = shift;
	if($table){
		$this->{dialplan} = $table;
		return $this->{dialplan};
	}
	else{
		return $this->{dialplan};
	}
}
sub extensions {
	my $this = shift;
	my $table = shift;
	if($table){
		$this->{extensions} = $table;
		return $this->{extensions};
	}
	else{
		return $this->{extensions};
	}
}

sub from_ip {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{from_ip} = $x;
		return $this->{from_ip};
	}
	else{
		return $this->{from_ip};
	}
}

sub handler {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{handler} = $x;
		return $this->{handler};
	}
	else{
		return $this->{handler};
	}
}

sub transfer {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{transfer} = $x;
		return $this->{transfer};
	}
	else{
		return $this->{transfer};
	}
}

# load the domain, site_key, user_id, and dial plan topic key
sub _loadContext {
	my $this = shift;
	my $handler = $this->{handler};
	my $dialplankey = $this->{dialplan};
	
	# get the domain, and dialplan
	# $this->{domain} = undef; # <-- derived from user id
	# Get the domain, user_id, site_key
	
	
	my $Domains = $handler->getTable('DialPlanToDomain');
	my $selectStatement = qq/SELECT domain_name, site_key FROM $Domains WHERE topic_key = ? ;/; # 1-topic_key
	my $selectHandler = $handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($dialplankey);
	my ($site_key,$domain);
	$selectHandler->bind_col( 1, \$domain );
	$selectHandler->bind_col( 2, \$site_key );
	while ($selectHandler->fetch) {
		$this->{domain} = $domain;
		$this->{site_key} = $site_key;
	}

	return undef unless $site_key;
	return 1;
}


=pod
---+ _loadDialPlan($extension)

This only loads those extensions from the Edittable that are relevant to the destination_number

Array: {
   "_row" : 1,
   "Order" : "1",
   "Extra" : "",
   "Time" : "30",
   "Target" : "1a3d565c-0fee-4129-8f50-49b43703cd1f",
   "Extension" : "2001",
   "Action" : "Call"
}
 {
   "_row" : 2,
   "Order" : "2",
   "Extra" : "",
   "Time" : "30",
   "Target" : "33cd6a12-c28e-46ca-9f43-1b727bfb816a",
   "Extension" : "2002",
   "Action" : "Call"
}

=cut
sub _loadExtensions {
	my $this = shift;
	my $handler = $this->{handler};
	$this->{extensions} = undef;
	
	my $dialplan_key = $this->dialplan;
	return undef unless $dialplan_key;
	my $DP = $handler->getTable('DialPlan');
	my $selectStatement = qq/SELECT dpl.row_number, dpl.row_blob
								FROM $DP dpl 
									WHERE dpl.topic_key = ? ;/; # 1- topic_key (dialplan_key)
	my $selectHandler = $handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($dialplan_key);
	my ($row_number,$row_blob);
	$selectHandler->bind_col( 1, \$row_number );
	$selectHandler->bind_col( 2, \$row_blob );
	require JSON;
	my @return_array;
	my @garbage;
	while ($selectHandler->fetch) {
		# the table is defined such that the rows are returned in order by topic_history_key, row_number
		my $perlRef = JSON::from_json($row_blob,{utf8 => 1});
		my $ext_num = $perlRef->{'Extension'};
		# direct match between the extension in the dial plan and the dialed number 
		if($perlRef->{'Extension'} eq $this->destination_number)
		{
			$this->_convertExtTargets($perlRef);
			push(@return_array,$perlRef);
			push(@garbage,$row_blob);			
		}
		elsif($perlRef->{'Extension'} eq $this->destination_number && $perlRef->{'Action'} eq 'Transfer'){
			# forward the call to an external number or another dial plan topic page
			$this->_convertExtTargets($perlRef);
			push(@return_array,$perlRef);
			push(@garbage,$row_blob);			
		}
		elsif($perlRef->{'Action'} eq 'Gateway' && $this->destination_number =~ /^\s*$ext_num([0-9]*)/){
			$this->_convertExtTargets($perlRef);
			push(@return_array,$perlRef);
			push(@garbage,$row_blob);			
		}
		
	}
	$this->extensions(\@return_array);

	return $this->extensions;
}


sub _regexTime {
	my $this = shift;
	my $perlRef = shift;
	my $time = $perlRef->{'Time'};
	# set default time to 30 seconds
	if($time =~ /^\s*([0-5]?[0-9])?\s*$/){
		$perlRef->{'Time'} = $1;
		return $perlRef->{'Time'};
	}
	#TODO: no time is present, so lets go with 30 seconds default (should be set in the Freeswitch Plugin setlib)
	$perlRef->{'Time'} = 30;
	return $perlRef->{'Time'};
}

sub _convertExtTargets {
	my $this = shift;
	my $perlRef = shift;	
	my $action = $perlRef->{'Action'};
	my $target = $perlRef->{'Target'};
	my $oldtarget = $target;
	my $method = 'Foswiki::Plugins::FreeswitchPlugin::Extension::_convert_'.$action;
	if ( defined &$method ) {
		no strict 'refs';
		#TODO split the target (could be comma delimited list)
		eval{
			$target = &$method($this,$target);	
		};
		if ($@) {
			# nothing came up for the target, revert to original content
			$target = $oldtarget;
		}
	}
	$perlRef->{'Target'} = $target;
}
# Changes (topic_key)->user_key or group_key
sub _convert_Call {
	my $this = shift;
	return $this->_changeTopicToUserOrGroup(@_);
}
# Pulls extensions from another Topic Page
sub _convert_Transfer {
	my $this = shift;
	return $this->_changeTopicToUserOrGroup(@_);
}


# Changes (topic_key)->user_key or group_key
sub _convert_VoiceMail {
	my $this = shift;
	return $this->_changeTopicToUserOrGroup(@_);
}

sub _changeTopicToUserOrGroup {
	my $this = shift;
	# the target is a topic_key
	my $target = shift;
	my $handler = $this->{handler};
	
	# check to see if it is a User
	my $Users = $handler->getTable('Users');
	my $selectStatement = qq/SELECT login_name FROM $Users WHERE topic_key = ? /; # 1-user_topic_key
	my $selectHandler = $handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($target);
	my ($login_name);
	$selectHandler->bind_col( 1, \$login_name );
	my @return_array;
	while ($selectHandler->fetch) {
		return $login_name;
	}
	# check to see if it is a Group
	return $target;	
}

=pod
---+ printXML()

Prints the xml to feed back to freeswitch

Array: {
   "_row" : 1,
   "Order" : "1",
   "Extra" : "",
   "Time" : "30",
   "Target" : "share.elmo",
   "Extension" : "2002",
   "Action" : "Call"
}

<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<document type="freeswitch/xml">
  <section name="dialplan" description="RE Dial Plan For FreeSwitch">
    <context name="default">
      <extension name="test9">
        <condition field="destination_number" expression="^83789$">
          <action application="bridge" data="iax/guest@conference.freeswitch.org/888"/>
        </condition>
      </extension>
    </context>
  </section>
</document>

=cut
sub printXML {
	my $this = shift;
	
	
	# for foswiki mapping
	my @options = @{$this->extensions};
	my @actionXML = ('<action application="set" data="domain_name='.$this->domain.'"/>','<action application="set" data="continue_on_fail=true"/>',
						'<action application="set" data="hangup_after_bridge=true"/>');
	
	my $origCount = scalar(@actionXML);
	foreach my $ext (@options){
		my ($ext_num,$action,$target,$time,$extra,$target_key) = ($ext->{'Extension'},$ext->{'Action'},$ext->{'Target'},$ext->{'Time'},$ext->{'Extra'},$ext->{'Target_Key'});
		my $method = 'Foswiki::Plugins::FreeswitchPlugin::Extension::_bridge_'.$action.'_';
		if ( defined &$method ) {
			no strict 'refs';
			push(@actionXML,&$method($this,$target,$time,$extra,$ext_num,$target_key));
        }
	}

	my $returnXML = join(' ',@actionXML) if scalar(@actionXML) > $origCount;
	return undef unless $returnXML; # make sure that there is something to return (not null dialplan) 
	
	$returnXML = '<condition field="destination_number" expression="^'.$this->destination_number.'$">'.$returnXML.'</condition>';
	$returnXML = '<extension name="'.$this->destination_number.'_'.$this->dialplan.'">'.$returnXML.'</extension>';
	$returnXML = '<context name="'.$this->dialplan.'">'.$returnXML.'</context>';
	$returnXML = '<document type="freeswitch/xml"><section name="dialplan">'.$returnXML.'</section></document>';
	return $returnXML;
}

=pod
---+ Bridgers
We only need 1 extension to give back?
      <extension name="test9">
        <condition field="destination_number" expression="^83789$">
          <action application="bridge" data="iax/guest@conference.freeswitch.org/888"/>
        </condition>
      </extension>
      
<extension name=”public_did”>
  <condition field=”destination_number” expression=”^(5551212)$”>
    <action application=”set” data=”call_timeout=18″/>
    <action application=”set” data=”continue_on_fail=true”/>
    <action application=”set” data=”hangup_after_bridge=true”/>
    <action application=”bridge” data=”sofia/switch.gruntnet/1000,sofia/switch.gruntnet/1001″/>
    <action application=”answer”/>
    <action application=”voicemail” data=”default $${domain} 1000″/>
  </condition>
</extension> 
      
=cut
sub _bridge_Call_ {
	my $this = shift;
	my ($target,$time,$extra,$ext_num) = @_;
	# TODO: assume $target is a comma delimited list
	my $xml;
	#$xml = '<action application="set" data="call_timeout='.$time.'"/>';
	$xml = '';
	#$xml .= '<action application="set" data="sip_h_Route=<sip:172.17.0.1;lr>" />';
	$xml .= '<action application="bridge" data="[leg_timeout='.$time.']sofia/internal/'.$target.'@'.$this->domain.'" />';
	return $xml;
}
sub _bridge_VoiceMail_ {
	my $this = shift;
	my ($target,$time,$extra,$ext_num) = @_;
	my $xml;
	$xml = '<action application=”answer”/>';
	$xml = '<action application="voicemail" data="'.$this->dialplan.' '.$this->domain.' $1"/>';
	$xml = '';
	return $xml;	
}

sub _bridge_Gateway_ {
	my $this = shift;
	my ($target,$time,$extra,$ext_num) = @_;
	my $local_call = 0;
	if($extra =~ /\s*Local\s*/i){
		$local_call = 1;
	}
	
	# Target should be System.FreeswitchPlugin
	my $dest_num = $this->destination_number;
	# strip off the extension number
	my $raw_num = $dest_num;
	if($raw_num =~ /^\s*$ext_num([0-9]*)/){
		$raw_num = $1;
	}

	#TODO: Find out what the local area code is
	
	# get the sofia string sofia/gateway/icall/$1 , etc
	my $sofia_string = $this->_ExternalPhoneSplitter($raw_num,$local_call);
	# get the number minus the 8
	my $xml;
	$xml = '<action application="bridge" data="[leg_timeout='.$time.']'.$sofia_string.'" />';
	return $xml;
	
}

sub _bridge_Transfer_ {
	my $this = shift;
	my ($target,$time,$extra,$ext_num,$target_key) = @_;
	#	Order 	Extension 		Action 		Target 					Time 	Extra
	#	1 		81345001085 	Transfer 	tokyo.e-flamingo.net 	30 	  
	my $xml;
	my $old_target = $target;
	my @targets = split(',',$old_target);

	if($targets[0] =~ m/^[0-9]+$/ && !$target_key){
		# this is an international number
		# hopefully the other Dialplan Topic pages aren't named after numbers....
		my @sofia_strings;
		foreach my $t1 (@targets){
			push(@sofia_strings,'[leg_timeout='.$time.']'.$this->_ExternalPhoneSplitter($target));
		}
		$xml = '<action application="bridge" data="'.join(',',@sofia_strings).'" />';
	}
	else{
		# need to get target key.....
		$xml = '<action application="transfer" data="'.$ext_num.' XML '.$target_key.'"/>';		
	}

	return $xml;
}
=pod

Country 	Zone 	Regex 	Other
Japan 	Landline 	^(0[2-9]\d{8})$ 	just land lines
Japan 	Mobile 	^(0[2-9]0\d{8})$ 	also includes IP phone numbers
USA 	All 	^([2-8]\d{9})$ 	  

=cut

my $GatewayByRegion = { 'USA' => {'code' => 1, 'All' => 'icall'}, 'Japan' => {'code' => 81, 'Mobile' => 'fusion', 'Landline'=> 'fusion'} };
my $CountryRegexes = { 
	'^1([2-8]\d{9})$' => {'country' => 'USA', 'type' => 'All'}, 
	'^81([1-9]\d{8})$' => {'country' => 'Japan', 'type' => 'Landline', 'local_ext' => '0'},
	'^81([2-9]0\d{8})$' => {'country' => 'Japan', 'type' => 'Mobile', 'local_ext' => '0' } 
};
my $NumberFormat = {'icall' => 'local', 'icall_international' => 'international', 'fusion' => 'local'};

# list of fusion gateways
my @fusion_numbers = ("81344557215","815058381711","815058381712","815058381713","815058381714","815058381715","815058381716",
	"815058381717","815058381718","815058381719","815058381720","815058381721","815058381722","815058381723","815058381724");

# ($country, $destination_number)-> gateway acceptable format
sub _ExternalPhoneSplitter {
	my $this = shift;
	my ($raw_num,$local) = @_;
	# raw_num means the number dialed is in international format

	my $gateway;
	foreach my $keyregex (keys %$CountryRegexes) {
		if($raw_num =~ /$keyregex/){
			
			my $country = $CountryRegexes->{$keyregex}->{'country'};
			my $type = $CountryRegexes->{$keyregex}->{'type'};
			my $local_ext = $CountryRegexes->{$keyregex}->{'local_ext'};
			$gateway = $GatewayByRegion->{$country}->{$type};

			my $clean_num = $local_ext.$1;
			# works for local calls only
			my $xml;
			$xml = 'sofia/gateway/'.$gateway.'/'.$clean_num;
			$xml = 'sofia/gateway/'.$gateway.'/'.$raw_num if $NumberFormat->{$gateway} eq 'international';
			# in Japan, unfortunately, we have to dial out of fusion
			if($gateway eq 'fusion'){
				$xml = 'sofia/gateway/fusion_'.$fusion_numbers[1].'/'.$clean_num;;
			}
			return $xml; 
		}
	}
	return undef;
}
# this function is to transfer callers to a different context
# (new_dial_plan_key)->extension to transfer call (prints xml)
sub _loadTransfer {
	my $this = shift;
	my $new_dial_plan_key = shift;
	my ($from_ip,$dirty_num) = ($this->from_ip,$this->destination_number);
	my $clean_num = _regexDiDToInternational($dirty_num,$from_ip);
	my $returnXML;
	
	my $ext;
	($ext->{'Extension'},$ext->{'Action'},$ext->{'Target'},$ext->{'Time'},$ext->{'Extra'},$ext->{'Target_Key'}) = 
		($clean_num,'Transfer',undef,undef,undef,$new_dial_plan_key);
	my @new_extensions;
	push(@new_extensions,$ext);
	$this->extensions(\@new_extensions);
}

# this is for when the call comes from a DiD and we need the public DiD
sub _getPublicDialPlan {
	my $this = shift;
	my $handler = $this->handler;
	my $dirty_number = $this->destination_number;
	my $from_ip = $this->from_ip;
	
	
	# make sure the dest num is in international format if the call is coming into the public context from a DiD
	my $clean_number = _regexDiDToInternational($dirty_number,$from_ip);
	# looking for the MPH value of EXTERNAL_DIALPLAN
	my ($Topics,$Sites,$did1,$mph) = ($handler->getTable('Topics'),$handler->getTable('Sites'),$handler->getTable('DiD_Inventory'),$handler->getTable('MetaPreferences'));

	my $selectStatement = qq/
  SELECT 
  mph1."value"
FROM 
  ($did1 did1 INNER JOIN $Sites s1 ON did1.site_key = s1."key") INNER JOIN
  ($Topics t1 INNER JOIN $mph mph1 ON mph1.topic_history_key = t1.link_to_latest)
	ON s1.local_preferences = t1."key" 
WHERE 
  did1.full_number = ? AND
  mph1."name" = 'EXTERNAL_DIALPLAN';/; # 1-full_number
	
	my $selectHandler = $handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute($clean_number);
	my ($dialplan_key);
	$selectHandler->bind_col( 1, \$dialplan_key );
	while ($selectHandler->fetch) {
		return $dialplan_key;
	}
	return undef;
}


###################################################################################################
  # this next section is to convert local numbers to international numbers
##################################################################################################

# put in either ip address or url
sub _getCountry{
	my $url = shift;
	
	my $provider_country = {
	'voip3006.agile.ne.jp' => '81', 
	'voip3017.agile.ne.jp' => '81',
	'sbc01-car.dal.us.icall.net' => '1',
	'gw01-car.dal.us.icall.net' => '1'	
	};
	my $provider_ip_hash = { 
	'61.196.178.246' => 'voip3006.agile.ne.jp', 
	'61.196.178.254' => 'voip3017.agile.ne.jp',
	'8.19.97.6' => 'sbc01-car.dal.us.icall.net',
	'74.112.133.173' => 'gw01-car.dal.us.icall.net',
	'72.249.14.242' => 'gw01-car.dal.us.icall.net',
	'61.213.230.156' => 'kwus.sip.0038.net',
	'voip3006.agile.ne.jp' => '61.196.178.246', 
	'voip3017.agile.ne.jp' => '61.196.178.254',
	'sbc01-car.dal.us.icall.net' => '8.19.97.6',
	'gw01-car.dal.us.icall.net' => '72.249.14.242',
	'kwus.sip.0038.net' => '61.213.230.156'
	};

	# guess that it is a url 
	return $provider_country->{$url} if $provider_country->{$url};
	
	# guess that it is an ip address
	my $ip = $url;
	return $provider_country->{$provider_ip_hash->{$ip}};
}
my $provider_dns_records = { 
	'61.196.178.246' => 'voip3006.agile.ne.jp', 
	'61.196.178.254' => 'voip3017.agile.ne.jp',
	'8.19.97.6' => 'sbc01-car.dal.us.icall.net',
	'72.249.14.242' => 'gw01-car.dal.us.icall.net',
	'61.213.230.156' => 'kwus.sip.0038.net'
};
my $fusion_050_to_03 = {
	'58381710' => '344557215'
};
my $provider_functions = {
	# agile_ne_jp will dump on 2012/01/31
	'voip3006.agile.ne.jp' => {
		'international' => '81', 
		'in' => sub {
			my $dirty_num = shift;
			my $clean_num;
			# Japan from Agile
			# strip the 0 off the first number
			$clean_num = '81'.substr( $dirty_num, 1);
			return $clean_num;			
		}
	}, 
	# agile_ne_jp sip trunk
	'voip3017.agile.ne.jp' => {
		'international' => '81', 
		'in' => sub {
			my $dirty_num = shift;
			my $clean_num;
			# Japan from Agile
			# strip the 0 off the first number
			$clean_num = '81'.substr( $dirty_num, 1);
			return $clean_num;			
		}
	}, 
	'sbc01-car.dal.us.icall.net' => {
		'international' => '1', 
		'in' => sub {
			my $dirty_num = shift;
			my $clean_num = $dirty_num;
			return $clean_num;			
		}
	}, 
	'gw01-car.dal.us.icall.net' => {
		'international' => '1', 
		'in' => sub {
			my $dirty_num = shift;
			my $clean_num = $dirty_num;
			return $clean_num;			
		}
	}, 
	# from fusion communication 050 numbers only
	'kwus.sip.0038.net' => {
		'international' => '81', 
		'in' => sub {
			my $dirty_num = shift;
			my $clean_num;
			$clean_num = '8150'.$dirty_num;
			# check to see if it is a 03 number
			$clean_num = '81'.$fusion_050_to_03->{$dirty_num} if $fusion_050_to_03->{$dirty_num};
			return $clean_num;
		}
	}
};

# changes the incoming did number to an international number
sub _regexDiDToInternational {
	my $dirty_num = shift;
	my $from_ip = shift;
	# maybe from_ip is actually a url, let's check
	my $provider_url = $from_ip if $provider_functions->{$from_ip}->{'international'};
	# if from_ip is actually an ip address, then get the url
	$provider_url = $provider_dns_records->{$from_ip} unless $provider_url;
	
	my $clean_num;
	
	# with the provider's name (url), get the function to convert the number to an international number
	$clean_num = $provider_functions->{$provider_url}->{'in'}->($dirty_num);	
	
	# TODO: put in some error checking function
	return $clean_num;
}


1;

__END__

External dial plan of tokyo.e-flamingo.net
1785ebc6-2e66-41ce-9735-e45438ff15d6

the Internal one
3ebe8fb5-3b20-40b3-a759-79196a9482f4

	my $turn = JSON::to_json(\@return_array, {utf8 => 1, pretty => 1});
	die "Turn: $turn";

hostname:(  virt-freeswitch03.e-flamingo.jp )
section:(  dialplan )
tag_name:(   )
key_name:(   )
key_value:(   )
Event-Name:(  REQUEST_PARAMS )
Core-UUID:(  50c37abd-34da-45e2-bdb3-c21dc0f418bf )
FreeSWITCH-Hostname:(  virt-freeswitch03.e-flamingo.jp )
FreeSWITCH-IPv4:(  172.16.0.21 )
FreeSWITCH-IPv6:(  ::1 )
Event-Date-Local:(  2011-07-08 12:32:38 )
Event-Date-GMT:(  Fri, 08 Jul 2011 03:32:38 GMT )
Event-Date-Timestamp:(  1310095958910942 )
Event-Calling-File:(  mod_dialplan_xml.c )
Event-Calling-Function:(  dialplan_xml_locate )
Event-Calling-Line-Number:(  379 )
Channel-State:(  CS_ROUTING )
Channel-State-Number:(  2 )
Channel-Name:(  sofiapath@tokyo.e-flamingo.net )
Unique-ID:(  2fcb0547-0dcb-4609-aa40-20098534040f )
Call-Direction:(  inbound )
Presence-Call-Direction:(  inbound )
Answer-State:(  ringing )
Channel-Read-Codec-Name:(  PCMA )
Channel-Read-Codec-Rate:(  8000 )
Channel-Write-Codec-Name:(  PCMA )
Channel-Write-Codec-Rate:(  8000 )
Caller-Username:(  share.elmo )
Caller-Dialplan:(  XML )
Caller-Caller-ID-Name:(  Share Elmo )
Caller-Caller-ID-Number:(  share.elmo )
Caller-Network-Addr:(  172.16.0.1 )
Caller-ANI:(  share.elmo )
Caller-Destination-Number:(  2001 )
Caller-Unique-ID:(  2fcb0547-0dcb-4609-aa40-20098534040f )
Caller-Source:(  mod_sofia )
Caller-Context:(  default )
Caller-Channel-Name:(  sofiapath@tokyo.e-flamingo.net )
Caller-Profile-Index:(  1 )
Caller-Profile-Created-Time:(  1310095958910942 )
Caller-Channel-Created-Time:(  1310095958910942 )
Caller-Channel-Answered-Time:(  0 )
Caller-Channel-Progress-Time:(  0 )
Caller-Channel-Progress-Media-Time:(  0 )
Caller-Channel-Hangup-Time:(  0 )
Caller-Channel-Transfer-Time:(  0 )
Caller-Screen-Bit:(  true )
Caller-Privacy-Hide-Name:(  false )
Caller-Privacy-Hide-Number:(  false )
variable_sip_received_ip:(  172.16.0.1 )
variable_sip_received_port:(  1539 )
variable_sip_via_protocol:(  udp )
variable_sip_from_user:(  share.elmo )
variable_sip_from_uri:(  share.elmo@tokyo.e-flamingo.net )
variable_sip_from_host:(  tokyo.e-flamingo.net )
variable_sip_from_user_stripped:(  share.elmo )
variable_sip_from_tag:(  liwke )
variable_sofia_profile_name:(  external )
variable_sip_req_user:(  2001 )
variable_sip_req_uri:(  2001@tokyo.e-flamingo.net )
variable_sip_req_host:(  tokyo.e-flamingo.net )
variable_sip_to_user:(  2001 )
variable_sip_to_uri:(  2001@tokyo.e-flamingo.net )
variable_sip_to_host:(  tokyo.e-flamingo.net )
variable_sip_contact_user:(  share.elmo )
variable_sip_contact_uri:(  share.elmo@192.168.2.247 )
variable_sip_contact_host:(  192.168.2.247 )
variable_channel_name:(  sofiapath@tokyo.e-flamingo.net )
variable_sip_call_id:(  uvdqpdcrxxbxjgn@acer-core2duo-akebono )
variable_sip_user_agent:(  Twinklepath )
variable_sip_via_host:(  192.168.2.247 )
variable_sip_via_rport:(  1539 )
variable_max_forwards:(  70 )
variable_switch_r_sdp:(  v=0
o=twinkle 1261949373 1081678288 IN IP4 192.168.2.247
s=-
c=IN IP4 192.168.2.247
t=0 0
m=audio 8000 RTPpath 98 97 8 0 3 101
a=rtpmap:98 speexpath
a=rtpmap:97 speexpath
a=rtpmap:8 PCMApath
a=rtpmap:0 PCMUpath
a=rtpmap:3 GSMpath
a=rtpmap:101 telephone-eventpath
a=fmtp:101 0-15
a=ptime:20
 )
variable_remote_media_ip:(  192.168.2.247 )
variable_remote_media_port:(  8000 )
variable_read_codec:(  PCMA )
variable_read_rate:(  8000 )
variable_write_codec:(  PCMA )
variable_write_rate:(  8000 )
variable_endpoint_disposition:(  RECEIVED )
Hunt-Username:(  share.elmo )
Hunt-Dialplan:(  XML )
Hunt-Caller-ID-Name:(  Share Elmo )
Hunt-Caller-ID-Number:(  share.elmo )
Hunt-Network-Addr:(  172.16.0.1 )
Hunt-ANI:(  share.elmo )
Hunt-Destination-Number:(  2001 )
Hunt-Unique-ID:(  2fcb0547-0dcb-4609-aa40-20098534040f )
Hunt-Source:(  mod_sofia )
Hunt-Context:(  default )
Hunt-Channel-Name:(  sofiapath@tokyo.e-flamingo.net )
Hunt-Profile-Index:(  1 )
Hunt-Profile-Created-Time:(  1310095958910942 )
Hunt-Channel-Created-Time:(  1310095958910942 )
Hunt-Channel-Answered-Time:(  0 )
Hunt-Channel-Progress-Time:(  0 )
Hunt-Channel-Progress-Media-Time:(  0 )
Hunt-Channel-Hangup-Time:(  0 )
Hunt-Channel-Transfer-Time:(  0 )
Hunt-Screen-Bit:(  true )
Hunt-Privacy-Hide-Name:(  false )
Hunt-Privacy-Hide-Number:(  false )
