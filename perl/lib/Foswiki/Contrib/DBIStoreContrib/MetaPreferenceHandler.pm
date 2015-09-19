# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler;
# MetaPreferences_History table -> subset of Topic_History
# See bottom of file for license and copyright information

use strict;
use warnings;


use Assert;

use IO::File   ();
use DBI	       ();
use File::Copy ();
use File::Spec ();
use File::Path ();
use Fcntl    qw( :DEFAULT :flock SEEK_SET );
use DBI				    ();
use DBD::Pg			    ();
use Data::UUID			    ();
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);
use File::Slurp qw(write_file);
use DBI qw(:sql_types);
use File::Basename				();
use Foswiki::Prefs::Parser		();
use Foswiki::Func			();
use Foswiki::Meta ();
use base ("Foswiki::Contrib::DBIStoreContrib::TopicHandler");


# (Handler object) -> MetaPreferenceHandler Object
# editing finally..... (delete later)
sub init {
	# TODO:check that the argument is a handler object First!
	# blah........
	my $class = shift;
	my $this = shift;
	return bless($this,$class);
}


my @MPListenerHash = (
sub {
	my ($this,$meta,$topicObject) = @_;	
	my ($name,$type,$valuesPre) = ($meta->{name},$meta->{type},$meta->{value});
	my @values = split(',',$valuesPre);
	my @valueKeyArray;
	foreach my $single_value (@values){
		my $value_key = $this->convert_MP($type, $name, $single_value, 'in');
		next unless $value_key;
		push(@valueKeyArray,$value_key);
	}

	my $valuesPost = join(',',@valueKeyArray);
	return { 'name' => $name, 'type' => $type, 'value' => $valuesPre, 'valuekey' => $valuesPost};
}
);

my @MPSaveHash = (
sub {  ## GROUP Topic Save -> User-Group member table change
	my ($this,$topicObject,$cUID,$th_row_ref,$meta_ref) = @_;
	my ($name,$type,$value) = ($meta_ref->{name},$meta_ref->{type},$meta_ref->{value});

	# { 'name' => $name, 'type' => $type, 'value' => $value, 'valuekey' => $valuekey}
	my @userlist = split(',',$value);
	my $topic_key = $th_row_ref->{topic_key};
	#require Foswiki::Contrib::DBIStoreContrib::GroupHandler;
	# we are phasing this out
	#Foswiki::Contrib::DBIStoreContrib::GroupHandler::insertUGRowByTopicKey($this,\@userlist,$topic_key);
	# 
	require Foswiki::Plugins::AccountsPlugin::DiDs;
	Foswiki::Plugins::AccountsPlugin::DiDs::changeOwnerViaMetaPreference($this,$name,$type,$value,$topicObject,$cUID,$th_row_ref,$meta_ref);

	return 1;

}
,
sub {
	my $this = shift;
	return undef;
}
);

my %SourceToMetaHash = (
'saveTopic' => {  ### - Start ####################################
### @vars=($topicObject, $cUID,\%th_row_ref)
'TOPICINFO' => sub { 
	return undef; 
},
'TOPICMOVED'=> sub { 
	return undef; 
},
'TOPICPARENT'=> sub { 
	return undef;
},
'FILEATTACHMENT'=> sub { 
	return undef; 
},
'FORM'=> sub { 
	return undef; 
},
'FIELD'=> sub { 
	return undef; 
},
'PREFERENCE'=> sub {
	my ($this,$topicObject, $cUID,$th_row_ref) = @_;


	my @prefs = $topicObject->find( 'PREFERENCE' );
	foreach my $pref (@prefs) {
		my ($name,$value,$type) = ($pref->{name},$pref->{valuekey},$pref->{type});
		$value = $pref->{value} unless $value;
		my $meta_ref = { 'name' => $name, 'value' => $value, 'topic_history_key' => $th_row_ref->{key}, 'type' => $type};
		my $valuekey = $pref->{valuekey};
		
		$this->insert_MP($meta_ref);
		# Run Save Listeners (in case other tables are affected)
		foreach my $mplistener (@MPSaveHash) {
			
			$mplistener->($this,$topicObject,$cUID,$th_row_ref,$meta_ref);
		}

	}
	#my @privates = $topicObject->find (  'PREFERENCE'  );
	#require Data::Dumper;
	#my $xxxx = Data::Dumper::Dumper(\ @prefs);
	#die $xxxx;
	return 1; 
}
},  #### saveTopic - Finished


'convertForSaveTopic'  => {  ### - Start ####################################
### @vars=($topicObject,$cUID,$options)
'TOPICINFO' => sub { 
	return undef; 
},
'TOPICMOVED'=> sub { 
	return undef; 
},
'TOPICPARENT'=> sub { 
	return undef; 
},
'FILEATTACHMENT'=> sub { 
	return undef; 
},
'FORM'=> sub { 
	return undef; 
},
'FIELD'=> sub { 
	return undef; 
},
'PREFERENCE'=> sub {
	my ($this,$topicObject,$cUID,$options) = @_;
	# need to expand some text
	my $dumbMeta = Foswiki::Meta->new( $Foswiki::Plugins::SESSION, $topicObject->web, $topicObject->topic );
	# scan the prefs in the meta data first
	my @prefs = $topicObject->find('PREFERENCE');

	# Scan the topic for Preference settings in the topic text next
	my $text = $topicObject->text;
	my ($type,$key,$value);
	foreach ( split( "\n", $text ) ) {
		my %currentpref;

		if (m/$Foswiki::regex{setVarRegex}/os) {
			$type  = $1;
			$key   = $2;
			$value = ( defined $3 ) ? $3 : '';
			if ( defined $type ) {
				%currentpref = ( 'type' => $type, 'name' => $key, 'value' => $value );
				push(@prefs,\%currentpref);
			}
        	}
		elsif ( defined $type ) {
			if ( /^(   |\t)+ *[^\s]/ && !/$Foswiki::regex{bulletRegex}/o ) {
				# follow up line, extending value
				$value .= "\n" . $_;
			}
			else {
				%currentpref = ( 'type' => $type, 'name' => $key, 'value' => $value );
				push(@prefs,\%currentpref);
				undef $type;
			}
		}

    }

	# do the modifications to the preference values
	foreach my $meta_ref ( @prefs  ) {
		
		my $mptypesHash = $this->LoadConversionTable();
		
		if($mptypesHash->{$meta_ref->{'name'}}->{'from'}){
			my ($mpfrom,$mpto) = ($mptypesHash->{$meta_ref->{'name'}}->{'from'},
				$mptypesHash->{$meta_ref->{'name'}}->{'to'});
			#die "in" if $meta_ref->{'name'} eq 'ADMINLOGIN';
			# expand the macros only if the preference must be saved as a topic/user/etc.. key!
			$meta_ref->{value} = $dumbMeta->expandMacros($meta_ref->{value});
			
		}
	
		
		# Run the Meta Listeners for each data type
		foreach my $mplistener (@MPListenerHash) {
			my $new_ref = $mplistener->($this,$meta_ref,$topicObject);
			$meta_ref = $new_ref if $new_ref;
		}
	}
	# put all the modified prefs back in the $topicObject
	foreach my $meta_ref2 ( @prefs  ) {
		$topicObject->putKeyed( 'PREFERENCE', 
		{ name => $meta_ref2->{'name'}, type => $meta_ref2->{'type'}, value => $meta_ref2->{'value'}, valuekey => $meta_ref2->{'valuekey'}});
	#die "Hi:".$meta_ref2->{'name'}."|".$meta_ref2->{'valuekey'}."|".$meta_ref2->{'value'}."NO" if $meta_ref2->{'name'} eq 'DOCWEB';
	}

	return 1; 
}
},  #### convertForSaveTopic - Finished


'readTopic'  => {  ### - Start ####################################
'TOPICINFO' => sub { 
	return undef; 
},
'TOPICMOVED'=> sub { 
	return undef; 
},
'TOPICPARENT'=> sub { 
	return undef; 
},
'FILEATTACHMENT'=> sub { 
	return undef; 
},
'FORM'=> sub { 
	return undef; 
},
'FIELD'=> sub { 
	return undef; 
},
'PREFERENCE'=> sub { 
	return undef; 
}
},  #### readTopic - Finished
'moveTopic'  => {  ### - Start ########## $throw_key  ##################
'rowCopy' => sub { 
	my ($this,$oldthkey,$newthkey) = @_;
	$this->move_MP($oldthkey,$newthkey);
	return undef; 
}
}, #### refreshTopic - Finished
'refreshTopic'  => {  ### - Start ########## $throw_key  ##################
'deleteEverything' => sub { 
	my ($this,$oldthkey) = @_;
	$this->delete_MP($oldthkey);
	return 1; 
}
} #### refreshTopic - Finished
);

############################################################################################
########################        Listener Call Distributor      #############################
############################################################################################
sub listener {
	my $site_handler = shift;
	my $sourcefunc = shift;
	my @vars = @_;
	# will need this after calling listeners in order to set the site_handler back to what it was before
	my $currentClass = ref($site_handler);
	# need to initialize the object
	my $this = Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler->init($site_handler);

	# these are pieces of the Meta topicObject		
	my @MetaHashObjects = ('TOPICINFO','TOPICMOVED','TOPICPARENT','FILEATTACHMENT','FORM','FIELD','PREFERENCE','CONTENT','LINKS');
	my $sourcFuncRef = $SourceToMetaHash{$sourcefunc};
	foreach my $MetaHash (@MetaHashObjects) {
		$SourceToMetaHash{$sourcefunc}{$MetaHash}->($this,@vars) if exists($SourceToMetaHash{$sourcefunc}{$MetaHash});
	}
	# return handler to previous state
	bless $this, $currentClass;
}
# move MetaPreference
# $this->move_MP();
sub move_MP {
	my ($this,$oldthkey,$newthkey) = @_;

	# sha1(1-topic_history_key, 2-name, 3-value) 
	my $MP = $this->getTableName('Meta_Preferences');
	my $insertStatement = qq/INSERT INTO $MP ("key", topic_history_key, "name", "value", "type")
		SELECT foswiki.sha1_uuid(foswiki.text2bytea(?||mp.name||mp.value)), ?, mp."name", mp."value", mp."type"
								FROM $MP mp WHERE mp.topic_history_key = ?/; # 1-$newthkey, 2-$newthkey, 3-$oldthkey
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->execute($newthkey,$newthkey,$oldthkey);
	return 0;
}

# insert MetaPreference
# $this->insert_MP({ name => $name, value => $value, topic_history_key => $th_row_ref->{key}, type => $type});
sub insert_MP {
	my ($this,$mphash) = @_;

	# sha1(1-topic_history_key, 2-name, 3-value) 
	$mphash->{'key'} = substr(sha1_hex($mphash->{'topic_history_key'},$mphash->{'name'},$mphash->{'value'}),0,-8);
	my $MP = $this->getTableName('Meta_Preferences');
	my $insertStatement = qq/INSERT INTO $MP ("key", topic_history_key, "name", "value", "type") VALUES (?,?,?,?,?);/;

	#warn "Name MP: $mphash->{'name'} and Value MP: $mphash->{'value'}\n";
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->bind_param( 1, $mphash->{'key'});
	$insertHandler->bind_param( 2, $mphash->{'topic_history_key'});
	$insertHandler->bind_param( 3, $mphash->{'name'});
	$insertHandler->bind_param( 4, $mphash->{'value'});
	$insertHandler->bind_param( 5, $mphash->{'type'});
	$insertHandler->execute;
	return $mphash->{'key'};

}

# insert MetaPreference
# $this->delete_MP($th_row_key);   deletes everything for this particular row
sub delete_MP {
	my ($this,$th_row_key) = @_;

	my $MP = $this->getTableName('Meta_Preferences');
	my $deleteStatement = qq/DELETE FROM $MP WHERE topic_history_key = ? ;/; # 1-topic_history_key

	#warn "Name MP: $mphash->{'name'} and Value MP: $mphash->{'value'}\n";
	my $deleteHandler = $this->database_connection()->prepare($deleteStatement);
	$deleteHandler->execute($th_row_key);
	return $th_row_key;

}
############################################################################################
########################            Fetching Functions         #############################
############################################################################################

sub fetchMPHValueByWTK {
	my ($this,$web_name,$topic_name,$key) = @_;
	#print "topichandler::fetchTopicKeyByWT()\n";
	my $th_key = $this->fetchTHKeyByWTR($web_name,$topic_name);
	return $this->fetchMPHValueByTHKey($th_key,$key);
}
sub fetchMPHValueByWebK {
	my ($this,$web_name,$key) = @_;
	my $web_key = $this->{web_cache}->{$web_name};
	return undef unless $web_key;
	
	# get the web key from the web name and the topic key of the web preferences
	my $topic_key = $this->{web_cache}->{$web_key}->{web_preferences};
	my $th_key = $this->fetchTHKeyByTopicKeyRevision($topic_key);
	return $this->fetchMPHValueByTHKey($th_key,$key);
}

sub fetchMPHValueByTHKey {
	my ($this,$th_key,$key) = @_;
	my $value = $this->{meta_cache}->{$th_key.$key};
	return $value unless $value;
	
	# else, we have to check memcache
	$value = $this->fetchMemcached('meta_cache',$th_key.$key);
	return $value;
}
############################################################################################
########################          Putting Functions            #############################
############################################################################################
sub putMPHValueByWTK {
	my ($this,$web_name,$topic_name,$key,$value) = @_;
	return undef unless $value && $key && $web_name && $topic_name;
	my $th_key = $this->fetchTHKeyByWTR($web_name,$topic_name);
	return undef unless $th_key;
	$this->{meta_cache}->{$th_key.$key} = $value;
	# and we have to check memcache
	$this->putMemcached('meta_cache',$th_key.$key,$value);
	return $value;
}
sub putMPHValueByTHKey {
	my ($this,$th_key,$key,$value) = @_;
	return undef unless $th_key && $key && $value;
	$this->{meta_cache}->{$th_key.$key} = $value;
	# and we have to check memcache
	$this->putMemcached('meta_cache',$th_key.$key,$value);
	return $value;
}
############################   General Purpose MetaPreference Insert   #################################

# LoadPreference($web,$topic,$key)->$value --> load a single preference
# if $topic is undef, then we need to get the WebPreference topic
sub LoadPreference {
	my ($this,$web,$topic,$mpName) = @_;
	my $web_key = $this->{web_cache}->{$web};
	my $site_key = $this->{site_key};
	my $Topics = $this->getTableName('Topics');
	my $Webs = $this->getTableName('Webs');
	my $MP = $this->getTableName('Meta_Preferences');
	
	# let's look up the value in the meta_cache
	my $pre_value;
	$pre_value = $this->fetchMPHValueByWTK($web,$topic,$mpName) if $web && $topic && $mpName;
	$pre_value = $this->fetchMPHValueByWebK($web,$mpName) if $web && !$topic && $mpName;
	return $pre_value if $pre_value;

	my $subSelectWebPref = qq/SELECT topics.link_to_latest FROM 
		  $Webs webs INNER JOIN $Topics topics ON webs.web_preferences = topics."key"
		WHERE webs."key" = ? AND webs.site_key = '$site_key'/; # 1-web_key

	my $subSelectTopicPref = qq/SELECT topics.link_to_latest FROM $Topics topics 
						  WHERE topics.current_web_key = ? AND
						  topics.current_topic_name = ? /; # 1-web_key 2-topic_name (bytea)
	my ($selectStatement,$bytea_tn);
	if(defined($topic)){
		# get topic preference
		$bytea_tn = sha1($topic);
		$selectStatement = qq/SELECT mp."value", mp.topic_history_key FROM $MP mp
			WHERE mp."name" = ? AND mp.topic_history_key = ($subSelectTopicPref);/;
	}else{
		# get web preference
		$selectStatement = qq/SELECT mp."value", mp.topic_history_key FROM $MP mp
			WHERE mp."name" = ? AND mp.topic_history_key = ($subSelectWebPref);/;
	}
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->bind_param( 1, $mpName);
	$selectHandler->bind_param( 2, $web_key);
	$selectHandler->bind_param( 3, $bytea_tn,{ pg_type => DBD::Pg::PG_BYTEA }) if defined($topic);

	$selectHandler->execute;
	my ($mpValue,$mp_th_key);
	$selectHandler->bind_col( 1, \$mpValue );
	$selectHandler->bind_col( 2, \$mp_th_key );
	while ($selectHandler->fetch) {
		# load it into memcache
		$this->putMPHValueByTHKey($mp_th_key,$mpName,$mpValue);
		return $mpValue;
	}
	return undef;
}
# LoadCascadeACLs($web,$topic,$mode)->\%hashOfkeys --> load all they keys for allow and deny
sub LoadCascadeACLs {
	my ($this,$web,$topic,$mode) = @_;
	my $web_key = $this->{web_cache}->{$web};
	my $site_key = $this->{site_key};
	my $Sites = $this->getTableName('Sites');
	my $Webs = $this->getTableName('Webs');
	my $Topics = $this->getTableName('Topics');
	my $MP = $this->getTableName('Meta_Preferences');
	my $bytea_tn = sha1($topic);

	# let's make the mp.name strings (one for ALLOW and one for DENY)
	my ($mtopic_allow,$mtopic_deny,$mweb_allow,$mweb_deny,$mroot_allow,$mroot_deny) = 
		('ALLOWTOPIC'.$mode,'DENYTOPIC'.$mode,'ALLOWWEB'.$mode,'DENYWEB'.$mode,'ALLOWROOT'.$mode,'DENYROOT'.$mode);

	# Alpha - get Local Topic Preferences
	# statement only to get local topic preference
	my %selectStatement;
	$selectStatement{Alpha} = qq/SELECT 
  mp."name", mp."value"
FROM 
  $MP mp
WHERE 
  mp."type" = 'Set'
  AND
  mp.topic_history_key = (SELECT topics.link_to_latest FROM $Topics topics 
  WHERE topics.current_web_key = ? AND topics.current_topic_name = ? ) 
  AND (mp."name" = ? OR mp."name" = ?) /; # 1-web_key 2-bytea-topic_name 3-mode_allow 4-mode_deny

	# Beta - get the Web Preferences
	$selectStatement{Beta} = qq/SELECT 
  mp."name", mp."value"
FROM 
  $MP mp
WHERE 
  mp."type" = 'Set'
  AND
  mp.topic_history_key = (SELECT topics.link_to_latest FROM $Topics topics 
  WHERE topics.key = (SELECT webs.web_preferences FROM $Webs webs WHERE 
                        webs."key" = ?))
  AND (mp."name" = ? OR mp."name" = ?) /; #  1-web_key 2-mode_allow 3-mode_deny

	# Gamma - get the Site Preferences
	$selectStatement{Gamma} = qq/SELECT 
  mp."name", mp."value"
FROM 
  $MP mp
WHERE 
  mp."type" = 'Set'
  AND
  mp.topic_history_key = (SELECT topics.link_to_latest FROM $Topics topics 
  WHERE topics.key = (SELECT sites.local_preferences FROM $Sites sites WHERE sites."key" = '$site_key' )  ) 
  AND (mp."name" = ? OR mp."name" = ?) /; # 1-mode_allow 2-mode_deny
	my %selectHandler;	
	$selectHandler{Alpha} = $this->database_connection()->prepare($selectStatement{Alpha});
	$selectHandler{Beta} = $this->database_connection()->prepare($selectStatement{Beta});
	$selectHandler{Gamma} = $this->database_connection()->prepare($selectStatement{Gamma});
	# bind parameters
	# ($mtopic_allow,$mtopic_deny,$mweb_allow,$mweb_deny,$mroot_allow,$mroot_deny)
	# Alpha 1-web_key 2-bytea-topic_name 3-mode_allow 4-mode_deny
	$selectHandler{Alpha}->bind_param( 1, $web_key);
	$selectHandler{Alpha}->bind_param( 2, $bytea_tn,{ pg_type => DBD::Pg::PG_BYTEA });
	$selectHandler{Alpha}->bind_param( 3, $mtopic_allow);
	$selectHandler{Alpha}->bind_param( 4, $mtopic_deny);
	# Beta  1-web_key 2-mode_allow 3-mode_deny
	$selectHandler{Beta}->bind_param( 1, $web_key);
	$selectHandler{Beta}->bind_param( 2, $mweb_allow);
	$selectHandler{Beta}->bind_param( 3, $mweb_deny);
	# Gamma 1-mode_allow 2-mode_deny
	$selectHandler{Gamma}->bind_param( 1, $mroot_allow);
	$selectHandler{Gamma}->bind_param( 2, $mroot_deny);

	# fetch the results
	$selectHandler{Alpha}->execute if $topic; # sometimes, we just want to find web permissions
	$selectHandler{Beta}->execute;
	$selectHandler{Gamma}->execute;
	my ($mpName,$mpValue);
	my $returnHash = {};
	# Topic Level Permissions
	if($topic){
		$selectHandler{Alpha}->bind_col( 1, \$mpName );
		$selectHandler{Alpha}->bind_col( 2, \$mpValue );
		while ($selectHandler{Alpha}->fetch) {
			$mpValue = $this->trim($mpValue);
			$returnHash->{TopicLevel}->{$mpName} = $mpValue || 'EMPTY';
		}		
	}

	# Web Level Permissions
	$selectHandler{Beta}->bind_col( 1, \$mpName );
	$selectHandler{Beta}->bind_col( 2, \$mpValue );
	while ($selectHandler{Beta}->fetch) {
		$mpValue = $this->trim($mpValue);
		$returnHash->{WebLevel}->{$mpName} = $mpValue || 'EMPTY';
	}
	# Site Level Permissions
	$selectHandler{Gamma}->bind_col( 1, \$mpName );
	$selectHandler{Gamma}->bind_col( 2, \$mpValue );
	while ($selectHandler{Gamma}->fetch) {
		$mpValue = $this->trim($mpValue);
		$returnHash->{SiteLevel}->{$mpName} = $mpValue || 'EMPTY';
	}

	return $returnHash;
}

=pod
---+ CascadePreference
For each topic revision, MetaPreference needs to know if the topic revision has already been parsed.  
To do that, we must define a preference where "name" = HASBEENSCOOPED = 1 


=cut
sub CascadePreference {
	my ($this,$web,$topic,$mode) = @_;
	
	my $site_key = $this->{site_key};
	my $web_key = $this->{web_cache}->{$web};
	my $user_key = $Foswiki::Plugins::SESSION->{user};
	my $topic_key = $this->_convert_WT_Topics_in($web.".".$topic);
	
	my ($topiclevelhash,$weblevelhash,$userlevelhash,$sitelevelhash);

	$topiclevelhash = $this->CascadePreferenceTopicLevel($topic_key);
	
	if(defined $topiclevelhash->{$mode} && $topiclevelhash->{$mode} =~ m/([a-zA-Z0-9]+)/){
		#die "TOPIC($mode,".$topiclevelhash->{$mode}.")" if $mode eq 'WEBCOPYRIGHT';
		return $topiclevelhash->{$mode};
	}
	#return $topiclevelhash->{$mode} if $topiclevelhash->{$mode};
	$weblevelhash = $this->CascadePreferenceWebLevel($web_key);
	if(defined $weblevelhash->{$mode} && $weblevelhash->{$mode} =~ m/([a-zA-Z0-9]+)/){
		#die "WEB($mode,".$weblevelhash->{$mode}.")" if $mode eq 'WEBCOPYRIGHT';
		return $weblevelhash->{$mode};
	}
	
	#return $weblevelhash->{$mode} if $weblevelhash->{$mode};
	
	$userlevelhash = $this->CascadePreferenceUserLevel($user_key);
	if(defined $userlevelhash->{$mode} && $userlevelhash->{$mode} =~ m/([a-zA-Z0-9]+)/){
		#die "USER($mode,".$userlevelhash->{$mode}.")" if $mode eq 'WEBCOPYRIGHT';
		return $userlevelhash->{$mode};
	}
	$sitelevelhash = $this->CascadePreferenceSiteLevel();
	if(defined $sitelevelhash->{$mode} && $sitelevelhash->{$mode} =~ m/([a-zA-Z0-9]+)/){
		#die "SITE($mode,".$sitelevelhash->{$mode}.")" if $mode eq 'WEBCOPYRIGHT';
		return $sitelevelhash->{$mode};
	}
	return undef;
}
# this only needs to be run once per Foswiki.pm session
# CascadePreferenceSiteLevel()->{$mpName} = $mpValue
sub CascadePreferenceSiteLevel {
	my ($this) = @_;
	my $returnHash = {};
	
	# we have to load the topic_history_key for site_local preferences only
	my $th_site_row = $this->LoadTHRow($this->LoadWTFromTopicKey($this->{site_cache}->{local_preferences}));
	my $th_site_key = $th_site_row->{'key'};


	# first, check if the site prefs have been put into the Handler hash
	if($this->{'permission_cache'}->{'site'}){
		return $this->{'permission_cache'}->{'site'};
	}
=pod
	# first, check if the site prefs have been put into the Memcached cache
	my $returnCacheText = $this->fetchMemcached('permission_cache','site');
	if($returnCacheText){
		
		my @returnCacheArray = split("\n\n",$returnCacheText);
		foreach my $NameValuePair (@returnCacheArray){
			my @namevaluearray = split("\n",$NameValuePair);
			$returnHash->{'site'}->{$namevaluearray[0]} = $namevaluearray[1];
		}
		$this->{'permission_cache'}->{'site'} = $returnHash->{'site'};
		return $returnHash->{'site'};
	}
	# else, no site pref were stored in cache, and now we have to fetch everything else from the db
=cut
	my $site_key = $this->{site_key};
	my $Sites = $this->getTableName('Sites');
	my $Webs = $this->getTableName('Webs');
	my $Users = $this->getTableName('Users');
	my $Topics = $this->getTableName('Topics');
	my $TH = $this->getTableName('Topic_History');
	my $MP = $this->getTableName('Meta_Preferences');
	my $user_key = $Foswiki::Plugins::SESSION->{user};

	my $selectStatement = qq/
SELECT 
  'sitelocal' as level,
  mph."type", 
  mph."name", 
  mph."value"
FROM 
$Topics t1
	INNER JOIN $MP mph ON t1.link_to_latest = mph.topic_history_key
	INNER JOIN $Sites s1 ON t1."key" = s1.local_preferences
WHERE 
  s1."key" = ?  AND mph."type" = 'Set' 
UNION
SELECT 
  'site' as level,
  mph."type", 
  mph."name", 
  mph."value"
FROM 
$Topics t1
	INNER JOIN $MP mph ON t1.link_to_latest = mph.topic_history_key
	INNER JOIN $Sites s1 ON t1."key" = s1.default_preferences
WHERE 
  s1."key" = ? AND mph."type" = 'Set' 
/;
	
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	# bind parameters
	# ($mtopic_allow,$mtopic_deny,$mweb_allow,$mweb_deny,$mroot_allow,$mroot_deny)
	# Alpha 1-web_key 2-bytea-topic_name 3-mode_allow 4-mode_deny
	$selectHandler->bind_param( 1, $site_key);
	$selectHandler->bind_param( 2, $site_key);

	# fetch the results
	$selectHandler->execute;
	my ($mpLevel,$mpType,$mpName,$mpValue);
	
	$selectHandler->bind_col( 1, \$mpLevel );
	$selectHandler->bind_col( 2, \$mpType );
	$selectHandler->bind_col( 3, \$mpName );
	$selectHandler->bind_col( 4, \$mpValue );
	while ($selectHandler->fetch) {
		$returnHash->{$mpLevel}->{$mpName} = $mpValue;
		
	}
	# make sure that Local site prefs out rank default site prefs
	
	foreach my $localVar (keys %{ $returnHash->{'sitelocal'}}){
		my $templocal = $returnHash->{'sitelocal'}->{$localVar};
		$returnHash->{'site'}->{$localVar} = $templocal if $templocal;
	}
	# put the results into cache
	# newline separates mpName and mpValue, double newline separates different name/value pairs
	my @mpArray;
	foreach my $localVar (keys %{ $returnHash->{'site'}}){
		push(@mpArray,$localVar."\n".$returnHash->{'site'}->{$localVar});
	}	
	my $mpCacheText = join("\n\n",@mpArray);
	$this->putMemcached('permission_cache','site',$mpCacheText,60);
	$this->{'permission_cache'}->{'site'} = $returnHash->{'site'};
	# put the contents of the entire hash in Memcache
	return $returnHash->{'site'};
}
# Only run once per session per web
# CascadePreferenceWebLevel($web_key)->{$mpName} = $mpValue
sub CascadePreferenceWebLevel {
	my ($this,$web_key) = @_;
	return undef unless $web_key;
	
	my $site_key = $this->{site_key};
	my $returnHash = {};
	
	# we have to load the topic_history_key for site_local preferences only
	my $th_web_row = $this->LoadTHRow($this->LoadWTFromTopicKey($this->{web_cache}->{$web_key}->{web_preferences}));
	my $th_web_key = $th_web_row->{'key'};
	
	die "Web Level Cascade function not working!" unless $th_web_key;
	
	
	# first, check if the site prefs have been put into the Handler hash
	if($this->{'permission_cache'}->{'web'.$th_web_key}){
		return $this->{'permission_cache'}->{'web'.$th_web_key};
	}
	# first, check if the site prefs have been put into the Memcached cache
	my $returnCacheText = $this->fetchMemcached('permission_cache','web'.$th_web_key);
	if($returnCacheText){
		my @returnCacheArray = split("\n\n",$returnCacheText);
		foreach my $NameValuePair (@returnCacheArray){
			my @namevaluearray = split("\n",$NameValuePair);
			$returnHash->{'web'}->{$namevaluearray[0]} = $namevaluearray[1];
		}
		$this->{'permission_cache'}->{'web'.$th_web_key} = $returnHash->{'web'};
		return $returnHash->{'web'};
	}
	# else, no site pref were stored in cache, and now we have to fetch everything else from the db	

	my $Sites = $this->getTableName('Sites');
	my $Webs = $this->getTableName('Webs');
	my $Users = $this->getTableName('Users');
	my $Topics = $this->getTableName('Topics');
	my $TH = $this->getTableName('Topic_History');
	my $MP = $this->getTableName('Meta_Preferences');
	my $user_key = $Foswiki::Plugins::SESSION->{user};

	my $selectStatement = qq/
SELECT 
  'web' as level,
  mph."type", 
  mph."name", 
  mph."value"
FROM 
$Topics t1
	INNER JOIN $MP mph ON t1.link_to_latest = mph.topic_history_key
	INNER JOIN $Webs w1 ON t1."key" = w1.web_preferences
WHERE 
  w1."key" = ? AND mph."type" = 'Set' 
/; 
	
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	# bind parameters
	# ($mtopic_allow,$mtopic_deny,$mweb_allow,$mweb_deny,$mroot_allow,$mroot_deny)
	# Alpha 1-web_key 2-bytea-topic_name 3-mode_allow 4-mode_deny
	$selectHandler->bind_param( 1, $web_key);

	# fetch the results
	$selectHandler->execute;
	my ($mpLevel,$mpType,$mpName,$mpValue);

	$selectHandler->bind_col( 1, \$mpLevel );
	$selectHandler->bind_col( 2, \$mpType );
	$selectHandler->bind_col( 3, \$mpName );
	$selectHandler->bind_col( 4, \$mpValue );
	
	my @mpArray;
	while ($selectHandler->fetch) {
		$returnHash->{$mpLevel}->{$mpName} = $mpValue;
		push(@mpArray,$mpName."\n".$mpValue);
	}
	# make sure future Cascade calls know that this page has been scooped
	$returnHash->{'web'}->{'HASBEENSCOOPED'} = 1;
	push(@mpArray,'HASBEENSCOOPED'."\n".'1');
	
	my $mpCacheText = join("\n\n",@mpArray);
	$this->putMemcached('permission_cache','web'.$th_web_key,$mpCacheText);
	$this->{'permission_cache'}->{'web'.$th_web_key} = $returnHash->{'web'};
	return $returnHash->{'web'};
}

# Only run once per session per user
# CascadePreferenceUserLevel($user_key)->{$mpName} = $mpValue
sub CascadePreferenceUserLevel {
	my ($this,$user_key) = @_;
	# let's just ignore user preferences for now
	return undef;
	
	return undef unless $user_key;
	#return undef unless $user_key;
	
	
	my $site_key = $this->{site_key};
	my $returnHash = {};
	# first, check if the site prefs have been put into the Handler hash
	if($this->{'permission_cache'}->{'user'.$user_key}){
		return $this->{'permission_cache'}->{'user'.$user_key};
	}
	# first, check if the site prefs have been put into the Memcached cache
	my $returnCacheText = $this->fetchMemcached('permission_cache','user'.$user_key);
	if($returnCacheText){
		my @returnCacheArray = split("\n\n",$returnCacheText);
		foreach my $NameValuePair (@returnCacheArray){
			my @namevaluearray = split("\n",$NameValuePair);
			$returnHash->{'user'}->{$namevaluearray[0]} = $namevaluearray[1];
		}
		$this->{'permission_cache'}->{'user'.$user_key} = $returnHash->{'user'};
		return $returnHash->{'user'};
	}
	# else, no site pref were stored in cache, and now we have to fetch everything else from the db	

	my $Sites = $this->getTableName('Sites');
	my $Webs = $this->getTableName('Webs');
	my $Users = $this->getTableName('Users');
	my $Topics = $this->getTableName('Topics');
	my $TH = $this->getTableName('Topic_History');
	my $MP = $this->getTableName('Meta_Preferences');

	my $selectStatement = qq/
SELECT 
  'user' as level,
  mph."type", 
  mph."name", 
  mph."value"  
FROM 
$Topics t1 
	INNER JOIN $MP mph ON t1.link_to_latest = mph.topic_history_key 
	INNER JOIN $Users u1 ON t1."key" = u1.user_topic_key 
WHERE 
  u1."key" = ? AND mph."type" = 'Set' 
/; 
	
	my $selectHandler = $this->database_connection()->prepare($selectStatement);

	# fetch the results
	$selectHandler->execute($user_key);
	my ($mpLevel,$mpType,$mpName,$mpValue);

	$selectHandler->bind_col( 1, \$mpLevel );
	$selectHandler->bind_col( 2, \$mpType );
	$selectHandler->bind_col( 3, \$mpName );
	$selectHandler->bind_col( 4, \$mpValue );
	
	my @mpArray;
	while ($selectHandler->fetch) {
		$returnHash->{$mpLevel}->{$mpName} = $mpValue;
		push(@mpArray,$mpName."\n".$mpValue);
	}
	# make sure future Cascade calls know that this page has been scooped
	$returnHash->{'user'}->{'HASBEENSCOOPED'} = 1;
	push(@mpArray,'HASBEENSCOOPED'."\n".'1');
	
	
	my $mpCacheText = join("\n\n",@mpArray);
	$this->putMemcached('permission_cache','user'.$user_key,$mpCacheText);
	$this->{'permission_cache'}->{'user'.$user_key} = $returnHash->{'user'};
	return $returnHash->{'user'};
}
# CascadePreferenceTopicLevel($topic_key)->{$mpName} = $mpValue
sub CascadePreferenceTopicLevel {
	my ($this,$topic_key) = @_;
	return undef unless $topic_key;
	my $site_key = $this->{site_key};
	# find the topic_history_key
	my $th_topic_row = $this->LoadTHRow($this->LoadWTFromTopicKey($topic_key));
	my $th_topic_key = $th_topic_row->{'key'};
	
	my $returnHash = {};
	# first, check if the site prefs have been put into the Handler hash
	if($this->{'permission_cache'}->{'topic'.$th_topic_key}){
		return $this->{'permission_cache'}->{'topic'.$th_topic_key};
	}
	# first, check if the site prefs have been put into the Memcached cache
	my $returnCacheText = $this->fetchMemcached('permission_cache','topic'.$th_topic_key);
	
	if($returnCacheText){
		
		my @returnCacheArray = split("\n\n",$returnCacheText);
		foreach my $NameValuePair (@returnCacheArray){
			my @namevaluearray = split("\n",$NameValuePair);
			$returnHash->{'topic'}->{$namevaluearray[0]} = $namevaluearray[1];
		}
		$this->{'permission_cache'}->{'topic'.$th_topic_key} = $returnHash->{'topic'};
		return $returnHash->{'topic'};
	}
	# else, no site pref were stored in cache, and now we have to fetch everything else from the db	
	die "Too many times ($topic_key,$th_topic_key)" if $this->{'permission_cache'}->{$topic_key} > 3;


	my $Sites = $this->getTableName('Sites');
	my $Webs = $this->getTableName('Webs');
	my $Users = $this->getTableName('Users');
	my $Topics = $this->getTableName('Topics');
	my $TH = $this->getTableName('Topic_History');
	my $MP = $this->getTableName('Meta_Preferences');

	my $selectStatement = qq/
SELECT 
  'topic' as level,
  mph."type", 
  mph."name", 
  mph."value"
FROM 
$TH th 
	INNER JOIN $MP mph ON th."key" = mph.topic_history_key
	INNER JOIN $Topics t1 ON th."key" = t1.link_to_latest
WHERE 
  t1."key" = ? AND mph."type" = 'Set' 
/; 
	
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	# bind parameters
	# ($mtopic_allow,$mtopic_deny,$mweb_allow,$mweb_deny,$mroot_allow,$mroot_deny)
	# Alpha 1-web_key 2-bytea-topic_name 3-mode_allow 4-mode_deny
	$selectHandler->bind_param( 1, $topic_key);

	# fetch the results
	$selectHandler->execute;
	my ($mpLevel,$mpType,$mpName,$mpValue);

	$selectHandler->bind_col( 1, \$mpLevel );
	$selectHandler->bind_col( 2, \$mpType );
	$selectHandler->bind_col( 3, \$mpName );
	$selectHandler->bind_col( 4, \$mpValue );
	
	my @mpArray;
	while ($selectHandler->fetch) {
		$returnHash->{$mpLevel}->{$mpName} = $mpValue;
		push(@mpArray,$mpName."\n".$mpValue);
	}
	$returnHash->{'topic'}->{'HASBEENSCOOPED'} = 1;
	push(@mpArray,'HASBEENSCOOPED'."\n".'1');
	
	my $mpCacheText = join("\n\n",@mpArray);
	$this->putMemcached('permission_cache','topic'.$th_topic_key,$mpCacheText);
	$this->{'permission_cache'}->{'topic'.$th_topic_key} = $returnHash->{'topic'};
	
	# testing
	$this->{'permission_cache'}->{$topic_key} = 1 unless $this->{'permission_cache'}->{$topic_key};
	$this->{'permission_cache'}->{$topic_key} += 1 if $this->{'permission_cache'}->{$topic_key};
	return $returnHash->{'topic'};
}
# extract preferences from the text
sub _extractPrefFromText {
	my @prefs;
	my $text = shift;
	my ($type,$key,$value);
	foreach ( split( "\n", $text ) ) {
		my %currentpref;

		if (m/$Foswiki::regex{setVarRegex}/os) {
			$type  = $1;
			$key   = $2;
			$value = ( defined $3 ) ? $3 : '';
			if ( defined $type ) {
				%currentpref = ( 'type' => $type, 'name' => $key, 'value' => $value );
				push(@prefs,\%currentpref);
			}
        	}
		elsif ( defined $type ) {
			if ( /^(   |\t)+ *[^\s]/ && !/$Foswiki::regex{bulletRegex}/o ) {
				# follow up line, extending value
				$value .= "\n" . $_;
			}
			else {
				%currentpref = ( 'type' => $type, 'name' => $key, 'value' => $value );
				push(@prefs,\%currentpref);
				undef $type;
			}
		}

    }
    return \@prefs;
}



1;
__END__

$this->{conversion_table}->{Users} 

	$selectStatement{Alpha} = qq/
SELECT 
  'topic' as level,
  mph."type", 
  mph."name", 
  mph."value"
FROM 
foswiki."Topic_History" th 
	INNER JOIN foswiki."MetaPreferences_History" mph ON th."key" = mph.topic_history_key
	INNER JOIN foswiki."Webs" w1 ON th.web_key = w1."key"
WHERE 
  w1."key" = ? AND th.topic_name = ? AND mph."name" = ? AND mph."type" = 'Set' 
UNION
SELECT 
  'web' as level,
  mph."type", 
  mph."name", 
  mph."value"
FROM 
foswiki."Topics" t1
	INNER JOIN foswiki."MetaPreferences_History" mph ON t1.link_to_latest = mph.topic_history_key
	INNER JOIN foswiki."Webs" w1 ON t1."key" = w1.web_preferences
WHERE 
  w1."key" = ? AND mph."name" = ? AND mph."type" = 'Set' 
UNION
SELECT 
  'sitelocal' as level,
  mph."type", 
  mph."name", 
  mph."value"
FROM 
foswiki."Topics" t1
	INNER JOIN foswiki."MetaPreferences_History" mph ON t1.link_to_latest = mph.topic_history_key
	INNER JOIN foswiki."Sites" s1 ON t1."key" = s1.local_preferences
WHERE 
  s1."key" = ?  AND mph."name" = ? AND mph."type" = 'Set' 
UNION
SELECT 
  'sitedefault' as level,
  mph."type", 
  mph."name", 
  mph."value"
FROM 
foswiki."Topics" t1
	INNER JOIN foswiki."MetaPreferences_History" mph ON t1.link_to_latest = mph.topic_history_key
	INNER JOIN foswiki."Sites" s1 ON t1."key" = s1.default_preferences
WHERE 
  s1."key" = ? AND mph."name" = ? AND mph."type" = 'Set' ;/; # 1-webkey 2-bytea_topic 3-mode

=checkAccessPermission('SPIN', 'IncyWincy', undef, 'ThisTopic', 'ThatWeb', undef)= will return =true=.

SELECT 
  w1.current_web_name AS web, 
  bname."value" AS topic,
  array_agg(mph.name||'=>'||mph.value)
FROM 
  foswiki."Topics" t1
	INNER JOIN foswiki."Blob_Store" bname ON t1.current_topic_name = bname."key"
	LEFT JOIN foswiki."MetaPreferences_History" mph ON t1.link_to_latest = mph.topic_history_key
	INNER JOIN foswiki."Webs" w1 ON t1.current_web_key = w1."key",
  foswiki."Sites" s1
WHERE
  bname."value" = 'SitePreferences'
  AND w1.current_web_name = 'Main'
  AND w1.site_key = s1."key"
  AND s1.current_site_name = 'tokyo.e-flamingo.net'
  AND mph.name = 'EXTERNAL_DIALPLAN'
GROUP BY w1.current_web_name, bname."value";
