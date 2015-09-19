package Foswiki::Plugins::AccountsPlugin::Users;

use strict;
use Foswiki::Func();
use Digest::MD5 qw(md5 md5_hex md5_base64);

my $keyhash = {
	'site_key' => {},
	'topics' => {},
	'webs' => {},
};
# ($web,$topic)-> $topic_key
sub _add_topic_key {
	return "die";	
}

sub refresh_user_base {
	my $session = shift;
	my $request = $session->{request};
	my $web   = $session->{webName};
	my $topic = $session->{topicName};
	my $current_time = time();
	
	# get the db handler
	require Foswiki::Contrib::DBIStoreContrib::TopicHandler;
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $Sites = $topic_handler->getTableName('Sites');
	my $Users = $topic_handler->getTableName('Users');
	my $UH = $topic_handler->getTableName('User_History');
	my $Topics = $topic_handler->getTableName('Topics');
	
	# Need (login,user_key,email)
	# e-flamingo.net is hardcoded b/c we only want e-flamingo.net users
	my $selectStatement = qq/SELECT 
  uh1.login_name as "login",
  uh1.first_name,
  uh1.last_name,
  regexp_replace(uh1.user_key::text, '-', '','g') as user_key, 
  uh1.email,
  t1."key",
  t1.link_to_latest
FROM 
  $Users u1
	INNER JOIN $UH uh1 ON uh1."key" = u1.link_to_latest
	INNER JOIN $Sites s1 ON s1."key" = u1.site_key
	LEFT JOIN $Topics t1 ON t1.current_topic_name = foswiki.sha1bytea(regexp_replace(uh1.user_key::text, '-', '','g'))
WHERE 
  s1.current_site_name = 'e-flamingo.net';/; 

	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute;
	my ($login,$user_key,$email,$topic_key,$th_key,$first_name,$last_name);
	$selectHandler->bind_col( 1, \$login );
	$selectHandler->bind_col( 2, \$first_name );
	$selectHandler->bind_col( 3, \$last_name );
	$selectHandler->bind_col( 4, \$user_key );
	$selectHandler->bind_col( 5, \$email );
	$selectHandler->bind_col( 6, \$topic_key );
	$selectHandler->bind_col( 7, \$th_key );
	my %user_return;
	my @meta_array;
	while ($selectHandler->fetch) {
		# search for topics with the same user_key name in the Coverage web
		# most users will be anonymous, so just put in last name/ first name
		$last_name = $login unless $last_name;
		$first_name = 'Unknown' unless $first_name;
		
		my ($temp_meta,$temp_text,$temp_web,$temp_topic);
		
		# if the topic exists
		if($topic_key){
			($temp_web,$temp_topic) = $topic_handler->_convert_WT_Topics_out($topic_key);
			($temp_meta,$temp_text) = Foswiki::Func::readTopic($temp_web,$temp_topic);
		}
		# if the topic does not exist, create it
		else{
			# load the EFUserTemplate
			my $accTemplate_key = Foswiki::Func::getPreferencesValue('EFUSERTEMPLATE',$web);
			($temp_web,$temp_topic) = $topic_handler->_convert_WT_Topics_out($accTemplate_key);
			($temp_meta,$temp_text) = Foswiki::Func::readTopic($temp_web,$temp_topic);
			# change the topic name of the new EF User page
			$temp_meta->topic($user_key);
		}
		# Form Fields: LastName, FirstName, LoginName, UserKey, Country, Email, LastUpdate
		# ('name','title','value') 
		my ($field1,$field2,$field3,$field4,$field5,$field6,$field7);
		($field1->{'name'},$field2->{'name'},$field3->{'name'},$field4->{'name'},$field5->{'name'},$field6->{'name'},$field7->{'name'}) = 
			("LastName","FirstName","LoginName","UserKey","Country","Email","LastUpdate");
		($field1->{'title'},$field2->{'title'},$field3->{'title'},$field4->{'title'},$field5->{'title'},$field6->{'title'},$field7->{'title'}) = 
			("LastName","FirstName","LoginName","UserKey","Country","Email","LastUpdate");
		($field1->{'value'},$field2->{'value'},$field3->{'value'},$field4->{'value'},$field5->{'value'},$field6->{'value'},$field7->{'value'}) = 
			($last_name,$first_name,$login,$user_key,'Japan',$email,time());
		$temp_meta->putKeyed( 'FIELD', $field1 ) if $field1->{'value'};
		$temp_meta->putKeyed( 'FIELD', $field2 ) if $field2->{'value'};
		$temp_meta->putKeyed( 'FIELD', $field3 ) if $field3->{'value'};
		$temp_meta->putKeyed( 'FIELD', $field4 ) if $field4->{'value'};
		$temp_meta->putKeyed( 'FIELD', $field5 ) if $field5->{'value'};
		$temp_meta->putKeyed( 'FIELD', $field6 ) if $field6->{'value'};
		$temp_meta->putKeyed( 'FIELD', $field7 ) if $field7->{'value'};
		push(@meta_array,$temp_meta);
	}
	# Save all of the updates at the same time! so that we don't make a db connection each time we want to update

	my %opts01;
	$opts01{'nocommit'} = 1;
	$topic_handler->database_connection()->{AutoCommit} = 0;
	$topic_handler->database_connection()->{RaiseError} = 1;
	# evaluate
	eval{
		# must defer constraints until after the transaction is finished
		$topic_handler->set_to_deferred();
		foreach my $xmeta (@meta_array){
			$xmeta->save(%opts01);
		}		

		# commit the transaction
		$topic_handler->database_connection()->commit;
	};
	if ($@) {
		#die "Rollback - failed to save ($w01,$t01) for reason:\n ";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
		catch Error::Simple with {
            throw Foswiki::OopsException(
                'attention',
                def    => 'save_error',
                web    => $web,
                topic  => $topic,
                params => [ $@ ]
            );
        };
	}
	
	# redirect to the new page
	my $redirecturl = $session->redirectto(   $session->getScriptUrl( 1, 'view', $web, $topic ) );
	$session->redirect($redirecturl);
	return;
}

# ($session,$topic_handler,$user_info)
sub user_self_update {
	my ($session,$topic_handler,$user_info) = @_;
	# get user key
	my $user_key = $session->{user};
	# IMPORTANT
	# check that the user is not WikiGuest...
	
	# Need ("LastName","FirstName","LoginName","UserKey","Country","Email","LastUpdate")
	my $request = $session->{request};
	my $mapper = {
		'first_name' => "FirstName",
		'last_name' => "LastName",
		'email' => "Email",
		'country' => "Country",
		'timestamp_epoch' => "LastUpdate"
	};
	# get the current row for the user
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	require Foswiki::Contrib::DBIStoreContrib::UserHandler;
	$user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($user_handler);
	my $updatedVariables = $user_handler->loadUHRowByUserKey($user_key);
	
	# load the variables from the http request from the User (the ones that changed)
	foreach my $nvar01 (keys %$mapper){
		$updatedVariables->{$nvar01} = $request->param($mapper->{$nvar01});
		$updatedVariables->{$nvar01} = $nvar01 unless $updatedVariables->{$nvar01};
	}
	$updatedVariables->{'change_user_key'} = $user_key;
	$updatedVariables->{'timestamp_epoch'} = time();

	# run the email through a regex filter
	$updatedVariables->{'email'} = $session->isValidEmailAddress($updatedVariables->{'email'});
	
	$user_handler->database_connection()->{AutoCommit} = 0;
	$user_handler->database_connection()->{RaiseError} = 1;
	# evaluate
	eval{
		# must defer constraints until after the transaction is finished
		$user_handler->set_to_deferred();
		# insert the UH Row
		$user_handler->insertUHRow($updatedVariables);	
		# run first_name and last_name through a regex filter (using the topic regex filter with Non-Wiki name allowed)
		die unless $session->isValidTopicName($updatedVariables->{'first_name'},1);
		die unless $session->isValidTopicName($updatedVariables->{'last_name'},1);
		# commit the transaction
		$user_handler->database_connection()->commit;
	};
	if ($@) {
		#die "Rollback - failed to save ($w01,$t01) for reason:\n ";
		$user_handler->database_connection()->errstr;
		eval{
			$user_handler->database_connection()->rollback;
		};
		catch Error::Simple with {
            throw Foswiki::OopsException(
                'attention',
                def    => 'save_error',
                web    => $session->{webName},
                topic  => $session->{topicName},
                params => [ $@ ]
            );
        };
	}
	
	# might help sometime
	bless $user_handler, *Foswiki::Contrib::DBIStoreContrib::Handler;
}
# the user can change their own contact information
sub change_user_config {
	my $session = shift;
	my ($web,$topic) = ($session->{webName},$session->{topicName});
	my $user_key = $session->{user};
	my $request = $session->{request};
	# get the current row for the user
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	require Foswiki::Contrib::DBIStoreContrib::UserHandler;
	$user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($user_handler);
	
	# get the necessary parameters
	
	my %input = %{$user_handler->loadUHRowByUserKey($user_key)};
	my %old_input;
	$old_input{'first_name'} = $input{'first_name'};
	$old_input{'last_name'} = $input{'last_name'};
	$old_input{'login_name'} = $input{'login_name'};
	$old_input{'email'} = $input{'email'};
	$old_input{'callback_number'} = $input{'callback_number'};
	$old_input{'country'} = $input{'country'};
	$old_input{'password'} = $input{'password'};
	
	
	$input{'first_name'} = $request->param('first_name');
	$input{'last_name'} = $request->param('last_name');
	$input{'login_name'} = $request->param('login_name');
	$input{'email'} = $request->param('email');
	$input{'callback_number'} = $request->param('callback_number');
	$input{'country'} = $request->param('country');
	my $passU = $request->param('mypassword');
	
	if($input{'first_name'} && $session->isValidTopicName($input{'first_name'},1)){
		# nothing
	}
	else{
		$input{'first_name'} = $old_input{'first_name'};
	}
	if($input{'last_name'} && $session->isValidTopicName($input{'last_name'},1)){
		# nothing
	}
	else{
		$input{'last_name'} = $old_input{'last_name'};
	}
	if($input{'login_name'} && $input{'login_name'} =~ m/^[A-Z0-9][A-Z0-9.-_]+[A-Z0-9]$/i ){
		# make sure to change the password as well
		# user 1002 on domain 127.0.0.1 with password 1234
		#$input{'password'} = md5_hex($input{'login_name'}.':'.$Foswiki::cfg{SiteName}.':'.$old_input{'password'});
		
		# does not work!!  changing the login name in the middle of the session frags everything
		$input{'login_name'} = $old_input{'login_name'};
		$input{'password'} = $old_input{'password'};
	}
	else{
		$input{'login_name'} = $old_input{'login_name'};
		$input{'password'} = $old_input{'password'};
	}
	if($input{'email'} && $input{'email'} =~ m/^([a-z0-9!+$%&'*+-\/=?^_`{|}~.]+\@[a-z0-9\.\-]+)$/i){
		# nothing
	}
	else{
		$input{'email'} = $old_input{'email'};
	}
	if($input{'country'} && $session->isValidTopicName($input{'country'},1)){
		# nothing
	}
	else{
		$input{'country'} = $old_input{'country'};
	}
	if($input{'callback_number'} =~ m/^[0-9]+$/i ){
		# nothing
	}
	else{
		$input{'callback_number'} = $old_input{'callback_number'};
	}
	# before we write the data, check that the user password is correct
	# we need the login name to generate the md5 hash to send to the database
	my $auth_bool = $user_handler->checkPasswordByLoginName($old_input{'login_name'},$passU);

	#  if $request->param('login_name') && $request->param('login_name') =~ m/^[A-Z0-9][A-Z0-9.-_]+[A-Z0-9]$/i;
	$user_handler->database_connection()->{AutoCommit} = 0;
	$user_handler->database_connection()->{RaiseError} = 1;
	
	# evaluate
	eval{
		# must defer constraints until after the transaction is finished
		$user_handler->set_to_deferred();
		$user_handler->insertUHRow(\%input);
		die "Bad Password" unless $auth_bool;
		# commit the transaction
		$user_handler->database_connection()->commit;
	};
	if ($@) {
		
		$user_handler->database_connection()->errstr;
		eval{
			$user_handler->database_connection()->rollback;
		};
		#die "Rollback - failed to save for reason:\n $@";
		catch Error::Simple with {
            throw Foswiki::OopsException(
                'attention',
                def    => 'save_error',
                web    => $session->{webName},
                topic  => $session->{topicName},
                params => [ $@ ]
            );
        };
	}	
	bless $user_handler, *Foswiki::Contrib::DBIStoreContrib::Handler;
}
# wiki mark up which displays user info from User_History
sub user_info {
	my ($inWeb,$inTopic, $args) = @_;
	require Foswiki::Plugins;
	my $session = $Foswiki::Plugins::SESSION;
	require Foswiki::Func;
	my $field = Foswiki::Func::extractNameValuePair( $args, 'Field' );
	my $user_key = $session->{user};
	
	# get the current row for the user
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	require Foswiki::Contrib::DBIStoreContrib::UserHandler;
	$user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($user_handler);
	my %uh_row = %{$user_handler->loadUHRowByUserKey($user_key)};
	# using this hash mapper makes sure that other datapoints can't be selected
	# IE For security
	my %mapper;
	$mapper{'FirstName'} = 'first_name';
	$mapper{'LastName'} = 'last_name';
	$mapper{'LoginName'} = 'login_name';
	$mapper{'Email'} = 'email';
	$mapper{'Country'} = 'country';
	$mapper{'CallBackNumber'} = 'callback_number';
	return undef unless $mapper{$field};
	return $uh_row{$mapper{$field}};
}

##########################################################
####################### BITCOIN ##########################
##########################################################
sub bitcoin {
	my ($inWeb,$inTopic, $args) = @_;
	# get the main argument
	my $field = Foswiki::Func::extractNameValuePair( $args );
	# the name is in wiki form
	my $user_name = Foswiki::Func::extractNameValuePair( $args, 'user' );
	
	my $session = $Foswiki::Plugins::SESSION;
	# need to get the user_key
	my $user_key = $session->{user};
	# if there is a user_name, then set to $user_name
	# get the current row for the user
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	if($user_name){

		require Foswiki::Contrib::DBIStoreContrib::UserHandler;
		$user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($user_handler);
		require Foswiki::Func;
		my ($uweb,$utopic) = Foswiki::Func::normalizeWebTopicName($session->{_web},$user_name);
		$user_key = $user_handler->fetchcUIDwithWikiName($uweb,$utopic);
	}
	# check memcache first!
	require Foswiki::Contrib::DBIStoreContrib::Handler;
	
	
	# the user_key is the account name for bitcoin
	my $commands = {
		'balance' => {
			'method' => 'getbalance',
			'params' => [
				$user_key
			]
		},
		'address' => {
			'method' => 'getaccountaddress',
			'params' => [
				$user_key
			]
		}
	};
	my $command_input = $commands->{$field};
	return undef unless $command_input;
	
	require JSON::RPC::Client;
	
	my $client = new JSON::RPC::Client;
 
	$client->ua->credentials(
     '172.16.0.204:8332', 'jsonrpc', 'joeldejesus' => 'daikon0231888'  # REPLACE WITH YOUR bitcoin.conf rpcuser/rpcpassword
      );
 
	my $uri = 'http://172.16.0.204:8332/';
	my $obj = {
		method  => $command_input->{'method'},
		params  => $command_input->{'params'}
	};

	my $res = $client->call( $uri, $obj );
 	my $answer;
	if ($res){
		if ($res->is_error) { print "Error : ", $res->error_message; }
		else { $answer = $res->result; }
	} else {
		$answer = $client->status_line;
		$answer = '';
	}
	return $answer;
	
}
# this is called from Orders consume_withdrawal in order to get a list of customers
sub get_customer_list {
	my ($topic_handler) = shift;
	
	my $site_key = $topic_handler->getSiteKey();
	my $Sites = $topic_handler->getTableName('Sites');
	my $Users = $topic_handler->getTableName('Users');
	
	my $selectStatement = qq^
SELECT 
  u1."key", 
  u1.user_topic_key
FROM 
  $Users u1 INNER JOIN $Sites s1 ON u1.site_key = s1."key"
WHERE
  s1.current_site_name = 'e-flamingo.net'

	^; # 1-end_time
	
	my $selectHandler = $topic_handler->database_connection()->prepare($selectStatement);
	$selectHandler->execute();
	my ($user_key,$user_topic_key);
	$selectHandler->bind_col( 1, \$user_key );
	$selectHandler->bind_col( 2, \$user_topic_key );
	
	my $user_hash;
	while ($selectHandler->fetch) {
		$user_hash->{$user_key}->{'topic_key'} = $user_topic_key;
		$user_hash->{$user_key}->{'site_key'} = $site_key;
	}
	return $user_hash;
}

1;
__END__


SELECT 
  uh1.login_name AS "login", 
  regexp_replace(uh1.user_key::text, '-', '','g'), 
  uh1.email
FROM 
  foswiki."Users" u1
	INNER JOIN foswiki."User_History" uh1 ON uh1."key" = u1.link_to_latest
	INNER JOIN foswiki."Sites" s1 ON s1."key" = u1.site_key
WHERE 
  s1.current_site_name = 'e-flamingo.net';
---+ Update User DB
SELECT 
  uh1.login_name AS "login", 
  regexp_replace(uh1.user_key::text, '-', '','g') as user_key, 
  uh1.email,
  t1."key",
  t1.link_to_latest
FROM 
  foswiki."Users" u1
	INNER JOIN foswiki."User_History" uh1 ON uh1."key" = u1.link_to_latest
	INNER JOIN foswiki."Sites" s1 ON s1."key" = u1.site_key
	LEFT JOIN foswiki."Topics" t1 ON t1.current_topic_name = foswiki.sha1bytea(regexp_replace(uh1.user_key::text, '-', '','g'))
WHERE 
  s1.current_site_name = 'e-flamingo.net';

---+ testing
SELECT 
  uh.first_name, 
  uh.last_name, 
  uh.login_name, 
  uh.email, 
  uh.callback_number, 
  uh.country
FROM 
  foswiki."User_History" uh INNER JOIN foswiki."Users" u1 ON u1.link_to_latest = uh."key"
WHERE 
  uh.login_name = 'dejesus.joel';
