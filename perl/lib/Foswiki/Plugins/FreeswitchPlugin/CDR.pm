package Foswiki::Plugins::FreeswitchPlugin::CDR;

use XML::Simple ();
use XML::Parser ();
use XML::LibXML ();

use JSON ();
use POSIX qw(ceil);

use strict;
use warnings;


# ($cdr from Freeswitch, $handler)->CDR object
sub new {
	my $class = shift;
	my $cdr_txt = shift;
	my $handler = shift;
	my $this;

  
  	my $p1 = new XML::Parser(Style => 'Debug');

	# change the cdr_txt to a hash
	my $xml_cdr;
	#$xml_cdr = XML::Simple::XMLin($cdr_txt, ForceArray => 0);
	#$xml_cdr = $p1->parse($cdr_txt);
	$xml_cdr = XML::LibXML->load_xml(string => $cdr_txt);
	
	$this->{libXML_obj} = $xml_cdr;

	# set the db handler
	$this->{handler} = $handler;
	bless $this, $class;	
	return $this;
}
# (name)->value
sub getChannel {
	my $this = shift;
	my $x = shift;
	# return value
	
	return $_->to_literal foreach ( $this->{libXML_obj}->findnodes('/cdr/channel_data/'.$x) ) ;
}
# (name)->value
sub getVariables {
	my $this = shift;
	my $x = shift;
	# return value
	
	return $_->to_literal foreach ( $this->{libXML_obj}->findnodes('/cdr/variables/'.$x) ) ;
}

# returns call key (uuid)
sub key {
	my $this = shift;
	return $this->getVariables('uuid');
}

# returns seconds rounded up on default, but ('milliseconds')-> in milliseconds
sub billableTime {
	my $this = shift;
	my $unit = shift;
	return ceil($this->getVariables('billmsec')/1000) unless $unit;
	return $this->getVariables('billmsec') if $unit eq 'milliseconds';
	# if milliseconds is mispelled, return minus numbers
	return -1;
}

# when the call is picked up on the otherside
# epoch time
sub answer_epoch {
	my $this = shift;
	my $x = $this->getVariables('answer_epoch');
	return $x if $x;
	return time() unless $x;
}
sub domain {
	my $this = shift;
	return $this->getVariables('domain_name');
}
sub context {
	my $this = shift;
	return $this->getVariables('user_context');
}
sub caller {
	my $this = shift;
	return $_->to_literal foreach ( $this->{libXML_obj}->findnodes('/cdr/callflow/caller_profile/username') ) ;
}
# number dialed
sub destination {
	my $this = shift;
	return $_->to_literal foreach ( $this->{libXML_obj}->findnodes('/cdr/callflow/caller_profile/destination_number') ) ;
}
# full dial string of the call
sub last_arg {
	my $this = shift;
	return $this->getVariables('last_arg');
}
# ($@)->save_error only has a value if the last save didn't work
sub save_error {
	my $this = shift;
	my $err_txt = shift;
	$this->{_save_error} = $err_txt if $err_txt;
	return $this->{_save_error};
}
# save the record
sub save {
	my $this = shift;
	my $handler = $this->{handler};
	$handler->database_connection()->{AutoCommit} = 0;
	
	# get table names
	my $CH = $handler->getTable('Call_History');
	my $Users = $handler->getTable('Users');

	# get the variables
	my $call_uuid = $this->key;
	my $billsec = $this->billableTime;
	my $destination_number = $this->destination;
	my $answer_epoch = $this->answer_epoch;
	my $last_arg = $this->last_arg;
	my $context = $this->context;
	# get the user info (need both domain and user)
	my $domain = $this->domain;
	my $user_id = $this->caller;

	
	# figure out the callee user_key based on the domain name and login name in $last_arg
	# looks like: %5Bleg_timeout%3D10%5Dsofia/internal/share.elmo%40tokyo.e-flamingo.net
	my ($callee_login_name,$callee_domain);
	if($last_arg =~ m/^(.*)\/internal\/([^\/%]*)%\d{2}([^%]*)$/){
		($callee_login_name,$callee_domain) = ($2,$3);
	}

	#die "Call Info: ($call_uuid,$billsec,$destination_number,$answer_epoch,$last_arg,$context,$domain,$user_id)";
	## Check to see if this is worth saving ##
	my $bool = 1;
	$bool = 0 unless $billsec > 0;
	$bool = 0 unless $answer_epoch > 0;
	$bool = 0 unless( $last_arg && $context && $destination_number && $call_uuid && $user_id && $domain);
	#return undef if $bool;
	
	my ($insertStatement,$insertHandler,$source_number,$cdrStatement,$cdrHandler);
	
	my @input_vars;
	if($callee_login_name && $callee_domain){
		my $sub_caller = qq/SELECT u1.user_key FROM $Users u1 WHERE u1."domain" = ? AND u1.login_name = ? /;
		my $sub_callee = qq/SELECT u2.user_key FROM $Users u2 WHERE u2."domain" = ? AND u2.login_name = ? /;
		# this is if the person being called is a registered user on e-flamingo
		$insertStatement = qq/INSERT INTO $CH (call_uuid, billsec, destination_number, answer_epoch, last_arg, context, caller_key, callee_key, source_number )
			SELECT ?, ?, ?, ?, ?, ?, ($sub_caller), ($sub_callee), ? ;/;
			# 1-call_uuid, 2-billsec, 3-destination_number, 4-answer_epoch, 5-last_arg, 6-context, 7-domain, 8-user_id, 9-callee_domain,10-callee_login_name 11-source_number, 
		$insertHandler = $handler->database_connection()->prepare($insertStatement);
		if( $context eq 'public' || !$context){
			# the person calling is calling from an external number
			# make sure that the context is a uuid
			$context = undef;
			# make sure that there is either a user_id (uuid) or an external number (source_number)
			$source_number = $user_id;
			$user_id = undef;
		};
		
		@input_vars = ($call_uuid,$billsec,$destination_number,$answer_epoch,$last_arg,$context,$domain,$user_id,$callee_domain,$callee_login_name,$source_number);
	}
	elsif($context && $context ne 'public'){
		# internal phone call
		$insertStatement = qq/INSERT INTO $CH (call_uuid, billsec, destination_number, answer_epoch, last_arg, context, caller_key )
			SELECT ?, ?, ?, ?, ?, ?, u1.user_key
			FROM $Users u1
			WHERE u1."domain" = ? AND u1.login_name = ? ;/;
				 # 1-call_uuid, 2-billsec, 3-destination_number, 4-answer_epoch, 5-last_arg, 6-context, 7-domain, 8-user_id
		$insertHandler = $handler->database_connection()->prepare($insertStatement);
		@input_vars = ($call_uuid,$billsec,$destination_number,$answer_epoch,$last_arg,$context,$domain,$user_id);	
	}
	else{
		# external phone call
		$source_number = $user_id; # the user_id would be the external number calling the DiD
		$insertStatement = qq/INSERT INTO $CH (call_uuid, billsec, destination_number, answer_epoch, last_arg, source_number )
			VALUES (?, ?, ?, ?, ?, ?) ;/; # 1-call_uuid, 2-billsec, 3-destination_number, 4-answer_epoch, 5-last_arg, 6-source_number,7-callee_login, 8-callee_domain
		$insertHandler = $handler->database_connection()->prepare($insertStatement);
		@input_vars = ($call_uuid,$billsec,$destination_number,$answer_epoch,$last_arg,$source_number);	
	}

	eval { 
		$insertHandler->execute(@input_vars);
		$handler->database_connection()->commit; 
	};
	if ( $@ ) {
		# save the error into the CDR object
		die "Rollback - failed to save call\n($call_uuid,$billsec,$destination_number,$answer_epoch,$last_arg,$context,$domain,$user_id)\n for reason:\n $@ ";
		#$this->save_error("Rollback - failed to save call for reason:\n $@ ");
		$handler->database_connection()->errstr;
		eval{
			$handler->database_connection()->rollback;
		};
		return 0;
	}
	return 1;
}

# TODO: need to find a way to pull this info from DBISQLQuery.pm!!!!!!!!!!!!!!!!!!
my $cdr_cols = {
		'sender' => { from => 'WT',to =>'Users' ,name => 'caller_key'},
		'receiver' => { from => 'WT',to =>'Users' ,name => 'callee_key'},
		'callsec' => { from => '',to =>'' ,name => 'billsec'},
		'answertime' => { from => '',to =>'' ,name => 'answer_epoch'},
		'context' => { from => 'WT',to =>'Topics' ,name => 'context'},
		'source_number' => { from => '',to =>'' ,name => 'source_number'},
		'destination_number' => { from => '',to =>'' ,name => 'destination_number'}
};

# call_uuid, billsec, destination_number, answer_epoch, last_arg, context, caller_key, source_number, callee_key
# fetchCDRTopic($topic_key,'column name')->value
sub fetchCDRTopic {
	my ($topic_handler,$topic_key,$column_name) = @_;
	my ($from,$to);
	$from = 'WT';
	my $value_key = $topic_handler->{cdr_cache}->{$topic_key}->{$column_name};
	
	my ($w1,$t1);
	if($column_name eq 'caller_key' || $column_name eq 'callee_key' ){
		$to = 'Users';
		($w1,$t1) = $topic_handler->_convert_WT_Users_out($value_key);	
	}
	elsif($column_name eq 'context'){
		$to = 'Topics';
		($w1,$t1) = $topic_handler->_convert_WT_Topics_out($value_key);
	}
	# this value is returned
	my $value;
	if($w1 && $t1){
		$value = $w1.'.'.$t1;
	}
	elsif($column_name eq 'context'){
		# sometimes, the dial plan comes from another site, so put public instead
		$value = 'public';
	}
	else{
		$value = $value_key;
	}
	return $value;
}
# call_uuid, billsec, destination_number, answer_epoch, last_arg, context, caller_key, source_number, callee_key
# putCDRTopic($handler,$topic_key,'column name','value')
sub putCDRTopic {
	my ($topic_handler,$topic_key,$column,$value) = @_;
	$topic_handler->{cdr_cache}->{$topic_key}->{$column} = $value;
	return $topic_handler->{cdr_cache}->{$topic_key}->{$column};
}

  
# %PHONECDR{"sender/receiver/length/time/context/source_number/destination_number" topic="%TOPIC%" }%
sub PhoneCDRRenderer {
	my ($inWeb,$inTopic, $args) = @_;
	
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($handler);
	
	require Foswiki::Func;
	my $tx_wt = Foswiki::Func::extractNameValuePair( $args, 'topic' );
	$tx_wt = $inWeb.'.'.$inTopic unless $tx_wt;
	my $topic_key = $topic_handler->_convert_WT_Topics_in($tx_wt);
	
	# if the topic arg is wrong, kill the function
	return undef unless $topic_key;
	
	# get the main arguement
	my $data_point = Foswiki::Func::extractNameValuePair( $args );

	return undef unless $cdr_cols->{$data_point}->{'name'};
	
	# convert the user inputed column name to match the column name of the SQL server
	$data_point = $cdr_cols->{$data_point}->{'name'};
	
	# hope that the data desired is in cache
	return fetchCDRTopic($handler,$topic_key,$data_point) if fetchCDRTopic($handler,$topic_key,$data_point);
	
	# if not, then get it from the database
	my $CDR = $topic_handler->getTableName('CDR');
	my $CTS = $topic_handler->getTableName('CDR_Topics');
	
	my @col_list = ('call_uuid', 'billsec', 'destination_number', 'answer_epoch', 'last_arg', 'context', 'caller_key', 'source_number', 'callee_key');
	my $columns = 'cdr.'.join(', cdr.',@col_list);
	  
	my $selectStatement = qq/SELECT $columns 
	FROM  $CDR cdr INNER JOIN $CTS cdrts ON cdr.call_uuid = cdrts.call_history_key  
	WHERE cdrts.topic_key = ?/; #1-topic_key
	
	my $select_handler = $topic_handler->database_connection()->prepare($selectStatement);
	$select_handler->execute($topic_key);
	
	while (my @ref = @{ $select_handler->fetchrow_arrayref()} ) {
		return undef unless scalar(@ref) > 0;
		my $i = 0;
		foreach my $c1 (@col_list){
			putCDRTopic($handler,$topic_key,$c1,$ref[$i]);
			$i += 1;	
		}
		return fetchCDRTopic($handler,$topic_key,$data_point);
	}
	return undef;
	
	
}

1;
__END__



=pod
  call_uuid uuid NOT NULL,
  billsec integer NOT NULL,
  destination_number character varying NOT NULL,
  answer_epoch integer NOT NULL,
  last_arg character varying NOT NULL,
  context uuid,
  caller_key uuid,
  source_number character varying,
  callee_key uuid,
=cut
########## Start function ##############
-- Function: freeswitch.add_new_cdr_topic(uuid, integer, character varying, integer, character varying, uuid, uuid, character varying, uuid)

-- DROP FUNCTION freeswitch.add_new_cdr_topic(uuid, integer, character varying, integer, character varying, uuid, uuid, character varying, uuid);

CREATE OR REPLACE FUNCTION freeswitch.add_new_cdr_topic(call_uuid uuid, billsec integer, destination_number character varying, answer_epoch integer,
 last_arg character varying, context uuid, caller_key uuid, source_number character varying, callee_key uuid, did_user_key uuid, did_site_key uuid)
  RETURNS void AS
$BODY$
DECLARE
 sender_topic uuid;
 receiver_topic uuid;
 topic_key01 uuid := foswiki.uuid_generate_v4();
 link_to_latest01 uuid;
 user_key01 uuid;
 web_key01 uuid;
 topic_name01 text;
 topic_content01 text;
 topic_name_key bytea;
 topic_content_key bytea;
 revision01 integer := 1;
 sender_site freeswitch.cdr_user_owner_lookup%ROWTYPE;
 receiver_site freeswitch.cdr_user_owner_lookup%ROWTYPE;
 did_site freeswitch.cdr_user_owner_lookup%ROWTYPE;
 default_site foswiki."Sites"%ROWTYPE;
 timestamp_epoch01 integer := answer_epoch;
 default_web uuid := 'de8c7dd3-7240-4f71-bbf4-808aaaed4e7c'::uuid;
 default_guest_key uuid := 'bb588981-59ba-447d-9df7-61fd858029ce'::uuid;
BEGIN 

-- Get Web Key of the Main Web of the Caller
   SELECT home_web,admin_user,owner_key INTO sender_site
			FROM freeswitch.cdr_user_owner_lookup
			WHERE  user_key = caller_key;
   SELECT home_web,admin_user,owner_key INTO receiver_site
			FROM freeswitch.cdr_user_owner_lookup
			WHERE  user_key = callee_key;
   SELECT home_web,admin_user,guest_user INTO did_site
			FROM freeswitch.cdr_user_owner_lookup
			WHERE  site_key = did_site_key;

   topic_name01 := 'Call'||regexp_replace(call_uuid::text, '-', '');
   topic_content01 := '---+!! Call Record

%STARTSECTION{"comments"}%

%COMMENT{type="below"}% 

%ENDSECTION{"comments"}%
';

   topic_name_key := foswiki.sha1bytea(topic_name01);
   topic_content_key := foswiki.sha1bytea(topic_content01);
   -- insert the topic name and topic content
   --foswiki.insert_bs_new(topic_name_key,topic_name01,topic_name01,NULL);
   INSERT INTO foswiki."Blob_Store" ("key", "value") SELECT topic_name_key, topic_name01 WHERE NOT EXISTS (SELECT 1 FROM foswiki."Blob_Store" WHERE "key" = topic_name_key);
   INSERT INTO foswiki."Blob_Store" ("key", "value") SELECT topic_content_key, topic_content01 WHERE NOT EXISTS (SELECT 1 FROM foswiki."Blob_Store" WHERE "key" = topic_content_key);
   
   --foswiki.insert_bs_new(topic_content_key, topic_content01, topic_content01, NULL);


   IF caller_key IS NOT NULL THEN
	-- A1 insert sender
		topic_key01 := foswiki.uuid_generate_v4();
		web_key01 := sender_site.home_web;
		user_key01 := caller_key;
		link_to_latest01 := foswiki.sha1_uuid(foswiki.text2bytea(ARRAY_TO_STRING(ARRAY[topic_key01::text, user_key01::text, web_key01::text, timestamp_epoch01::text,topic_name_key::text,topic_content_key::text], '')));
		INSERT INTO foswiki."Topics" ("key", link_to_latest, current_web_key, current_topic_name)
			VALUES (topic_key01, link_to_latest01, web_key01, topic_name_key);
		

		INSERT INTO foswiki."Topic_History" ("key", topic_key, user_key, revision, web_key, timestamp_epoch, topic_content, topic_name)
			VALUES (link_to_latest01, topic_key01, user_key01, revision01, web_key01, timestamp_epoch01, topic_content_key, topic_name_key);
		sender_topic := topic_key01;
		INSERT INTO freeswitch."CDR_Topic_Mapper" (call_history_key,topic_key) VALUES (call_uuid,sender_topic);
	IF callee_key IS NOT NULL AND receiver_site.home_web != sender_site.home_web THEN
	-- B1 receiver is a private site user and is on a different site as the sender => must save 2 topics

		-- change sites for B1 and insert receiver
		topic_key01 := foswiki.uuid_generate_v4();
		web_key01 := receiver_site.home_web;
		user_key01 := callee_key;
		link_to_latest01 := foswiki.sha1_uuid(foswiki.text2bytea(ARRAY_TO_STRING(ARRAY[topic_key01::text, user_key01::text, web_key01::text, timestamp_epoch01::text,topic_name_key::text,topic_content_key::text], '')));
		INSERT INTO foswiki."Topics" ("key", link_to_latest, current_web_key, current_topic_name)
			VALUES (topic_key01, link_to_latest01, web_key01, topic_name_key);

		INSERT INTO foswiki."Topic_History" ("key", topic_key, user_key, revision, web_key, timestamp_epoch, topic_content, topic_name)
			VALUES (link_to_latest01, topic_key01, user_key01, revision01, web_key01, timestamp_epoch01, topic_content_key, topic_name_key);
		receiver_topic := topic_key01;
		-- load the cdr_topic linkers
		INSERT INTO freeswitch."CDR_Topic_Mapper" (call_history_key,topic_key) VALUES (call_uuid,receiver_topic);
		
	ELSIF callee_key IS NOT NULL THEN
	-- B1 receiver is a private site user and is on the same site as the sender => must save 1 topic
	-- do nothing, b/c situation was handled by inserting A1
	ELSE
	-- B2 e-flamingo.net default
		-- change sites for B1 to e-flamingo.net and insert receiver, we need the owner of the sender site (A1's site)
		topic_key01 := foswiki.uuid_generate_v4();
		web_key01 := default_web;
		user_key01 := sender_site.owner_key;
		link_to_latest01 := foswiki.sha1_uuid(foswiki.text2bytea(ARRAY_TO_STRING(ARRAY[topic_key01::text, user_key01::text, web_key01::text, timestamp_epoch01::text,topic_name_key::text,topic_content_key::text], '')));

		INSERT INTO foswiki."Topics" ("key", link_to_latest, current_web_key, current_topic_name)
			VALUES (topic_key01, link_to_latest01, web_key01, topic_name_key);
		INSERT INTO foswiki."Topic_History" ("key", topic_key, user_key, revision, web_key, timestamp_epoch, topic_content, topic_name)
			VALUES (link_to_latest01, topic_key01, user_key01, revision01, web_key01, timestamp_epoch01, topic_content_key, topic_name_key);
		receiver_topic := topic_key01;
		-- load the cdr_topic linkers
		
		INSERT INTO freeswitch."CDR_Topic_Mapper" (call_history_key,topic_key) VALUES (call_uuid,receiver_topic);
	END IF;

   ELSE
	-- B1 and sender is most definitely an external number, not a user on a private site (so A2, not A1)

	IF callee_key IS NOT NULL THEN
		-- change sites for B1 and insert receiver (A2->B1)
		topic_key01 := foswiki.uuid_generate_v4();
		web_key01 := receiver_site.home_web;
		user_key01 := callee_key;
		link_to_latest01 := foswiki.sha1_uuid(foswiki.text2bytea(ARRAY_TO_STRING(ARRAY[topic_key01::text, user_key01::text, web_key01::text, timestamp_epoch01::text,topic_name_key::text,topic_content_key::text], '')));
		INSERT INTO foswiki."Topics" ("key", link_to_latest, current_web_key, current_topic_name)
			VALUES (topic_key01, link_to_latest01, web_key01, topic_name_key);

		INSERT INTO foswiki."Topic_History" ("key", topic_key, user_key, revision, web_key, timestamp_epoch, topic_content, topic_name)
			VALUES (link_to_latest01, topic_key01, user_key01, revision01, web_key01, timestamp_epoch01, topic_content_key, topic_name_key);
		receiver_topic := topic_key01;
		
		INSERT INTO freeswitch."CDR_Topic_Mapper" (call_history_key,topic_key) VALUES (call_uuid,receiver_topic);

		-- change sites for A2 and insert sender (which is the owner_key on the receiver's site)
	   	topic_key01 := foswiki.uuid_generate_v4();
		web_key01 := default_web;
		user_key01 := receiver_site.owner_key;
		link_to_latest01 := foswiki.sha1_uuid(foswiki.text2bytea(ARRAY_TO_STRING(ARRAY[topic_key01::text, user_key01::text, web_key01::text, timestamp_epoch01::text,topic_name_key::text,topic_content_key::text], '')));
		INSERT INTO foswiki."Topics" ("key", link_to_latest, current_web_key, current_topic_name)
			VALUES (topic_key01, link_to_latest01, web_key01, topic_name_key);

		INSERT INTO foswiki."Topic_History" ("key", topic_key, user_key, revision, web_key, timestamp_epoch, topic_content, topic_name)
			VALUES (link_to_latest01, topic_key01, user_key01, revision01, web_key01, timestamp_epoch01, topic_content_key, topic_name_key);
		sender_topic := topic_key01;
		
		INSERT INTO freeswitch."CDR_Topic_Mapper" (call_history_key,topic_key) VALUES (call_uuid,sender_topic);
	ELSE
		-- someone from the outside PTSN network called an external number (A2->B2), use destination_number and DiD_Inventory to find the user_key/site_key
		IF did_site_key IS NOT NULL THEN
			-- B2 is a site, insert into the site indicated by the DiD_Invenory table
			topic_key01 := foswiki.uuid_generate_v4();
			web_key01 := did_site.home_web;
			user_key01 := did_site.guest_user;
			link_to_latest01 := foswiki.sha1_uuid(foswiki.text2bytea(ARRAY_TO_STRING(ARRAY[topic_key01::text, 
				(SELECT sa2b2.guest_user FROM foswiki."Sites" sa2b2 WHERE sa2b2."key" = did_site_key)::text, 
				web_key01::text, timestamp_epoch01::text,topic_name_key::text,topic_content_key::text], '')));
			INSERT INTO foswiki."Topics" ("key", link_to_latest, current_web_key, current_topic_name)
				VALUES (topic_key01, link_to_latest01, web_key01, topic_name_key);

			INSERT INTO foswiki."Topic_History" ("key", topic_key, user_key, revision, web_key, timestamp_epoch, topic_content, topic_name)
				SELECT link_to_latest01, topic_key01, sa2b2.guest_user, revision01, web_key01, timestamp_epoch01, topic_content_key, topic_name_key
				FROM foswiki."Sites" sa2b2 WHERE sa2b2."key" = did_site_key;
			receiver_topic := topic_key01;
			INSERT INTO freeswitch."CDR_Topic_Mapper" (call_history_key,topic_key) VALUES (call_uuid,receiver_topic);

		ELSIF did_user_key IS NOT NULL THEN
			-- B2 is an external number owned by a user on e-flamingo.net, therefore insert into e-flamingo.net
			topic_key01 := foswiki.uuid_generate_v4();
			web_key01 := default_web;
			user_key01 := did_user_key;
			link_to_latest01 := foswiki.sha1_uuid(foswiki.text2bytea(ARRAY_TO_STRING(ARRAY[topic_key01::text, user_key01::text, web_key01::text, timestamp_epoch01::text,topic_name_key::text,topic_content_key::text], '')));
			INSERT INTO foswiki."Topics" ("key", link_to_latest, current_web_key, current_topic_name)
				VALUES (topic_key01, link_to_latest01, web_key01, topic_name_key);

			INSERT INTO foswiki."Topic_History" ("key", topic_key, user_key, revision, web_key, timestamp_epoch, topic_content, topic_name)
				VALUES (link_to_latest01, topic_key01, user_key01, revision01, web_key01, timestamp_epoch01, topic_content_key, topic_name_key);
			receiver_topic := topic_key01;
		
			INSERT INTO freeswitch."CDR_Topic_Mapper" (call_history_key,topic_key) VALUES (call_uuid,receiver_topic);	
		END IF;
	END IF;

   END IF;

RETURN;

END;





$BODY$
  LANGUAGE 'plpgsql' VOLATILE
  COST 100;
ALTER FUNCTION freeswitch.add_new_cdr_topic(uuid, integer, character varying, integer, character varying, uuid, uuid, character varying, uuid) OWNER TO foswikiroot;


########## End function ##############
########## Start for Implementing Above Function ###########
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
UPDATE freeswitch."Call_History" 
SET 
  gateway = array_to_string(regexp_matches(last_arg, 'sofia\/gateway\/([^/]+)\/\d+'), ''),
  gateway_destination = array_to_string(regexp_matches(last_arg, 'sofia\/gateway\/[^/]+\/(\d+)'), '')
WHERE last_arg IS NOT NULL AND gateway IS NULL AND gateway_destination IS NULL;

SELECT 
freeswitch.add_new_cdr_topic(ch.call_uuid, ch.billsec , ch.destination_number , 
	ch.answer_epoch, ch.last_arg, ch.context, 
		ch.caller_key, ch.source_number, ch.callee_key,did.user_key,did.site_key) 
FROM 
  freeswitch."Call_History" ch
		LEFT JOIN freeswitch."CDR_Topic_Mapper" ctm ON ch.call_uuid = ctm.call_history_key
		LEFT JOIN accounts."DiD_Inventory" did ON ch.destination_number = did.full_number
WHERE
 ctm.call_history_key IS NULL AND did.full_number IS NOT NULL;
COMMIT;



########### End Use Above Function ########
---+ 



UPDATE  freeswitch."Call_History" ch
SET     callee_key = u1."key"
FROM    
  foswiki."Users" u1 
	INNER JOIN foswiki."User_History" uh ON u1.link_to_latest = uh."key"
	INNER JOIN foswiki."Sites" s1 ON u1.site_key = s1."key"
WHERE
  uh.login_name = regexp_replace(ch.last_arg, '^(.*)/([^/%]*)%\d{2}([^%]*)$', '\2') AND
  s1.current_site_name = regexp_replace(ch.last_arg, '^(.*)/([^/%]*)%\d{2}([^%]*)$', '\3');