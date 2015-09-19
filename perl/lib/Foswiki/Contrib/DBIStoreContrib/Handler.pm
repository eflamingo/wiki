# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::Handler;

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
use File::Basename		    ();
use Data::UUID			    ();
use Encode;
use Foswiki::Meta			();
use Foswiki::Iterator::NumberRangeIterator ();
use Cache::Memcached();

use utf8;

my $foswikinamespace = "foswiki";
my $accountsnamespace = "accounts";
my $freeswitchnamespace = "freeswitch";
my $handlerTables = { Topics => qq/$foswikinamespace."Topics"/, 
			Topic_History => qq/$foswikinamespace."Topic_History"/,
			Attachments => qq/$foswikinamespace."Attachments"/, Attachment_History => qq/$foswikinamespace."Attachment_History"/,
			Dataform_Data => qq/$foswikinamespace."Dataform_Data_History"/,Data_Field => qq/$foswikinamespace."Dataform_Data_Field"/,
			Definition_Field => qq/$foswikinamespace."Dataform_Definition_Field"/, 
			Dataform_Definition => qq/$foswikinamespace."Dataform_Definition_History"/, 
			Group_User_Membership => qq/$foswikinamespace."Group_User_Membership"/, Groups => qq/$foswikinamespace."Groups"/, 
			Group_History => qq/$foswikinamespace."Group_History"/, Links => qq/$foswikinamespace."Links"/, 
			Users => qq/$foswikinamespace."Users"/, User_History => qq/$foswikinamespace."User_History"/,
			Webs => qq/$foswikinamespace."Webs"/, Meta_Preferences => qq/$foswikinamespace."MetaPreferences_History"/,  
			Meta_Preferences_DataTypes => qq/$foswikinamespace."MetaPreferences_DataTypes"/,
			Blob_Store => qq/$foswikinamespace."Blob_Store"/,	Sites => qq/$foswikinamespace."Sites"/, Site_History => qq/$foswikinamespace."Site_History"/,
			PhoneUser_Lookup => qq/$freeswitchnamespace.user_lookup/, File_Store => qq/$foswikinamespace."File_Store"/ ,
			Web_History => qq/$foswikinamespace."Web_History"/, EditTableRows => qq/$foswikinamespace."EditTable_Data"/,
			Order_Book => qq/$accountsnamespace."Order_Book"/, Contracts => qq/$accountsnamespace."Contracts"/, Credit_History => qq/$accountsnamespace."Credit_History"/,
			Product_Catalog => qq/$accountsnamespace."Product_Catalog"/, Product_Owner => qq/$accountsnamespace."Product_Owner"/, 
			Site_Inventory => qq/$accountsnamespace."Site_Inventory"/, DiD_Inventory => qq/$accountsnamespace."DiD_Inventory"/,  Credit_Balance => qq/$accountsnamespace."Credits_Balance"/,
			Splits => qq/$accountsnamespace."Splits"/, CDR => qq/$freeswitchnamespace."Call_History"/, CDR_Topics => qq/$freeswitchnamespace."CDR_Topic_Mapper"/,
			BitCoinAddresses => qq/$accountsnamespace."BitCoin_Addresses"/
};

sub returnHandlerTables {
	my $table = shift;
	return $handlerTables->{$table};
}
sub startNewdbiconnection {
	# Setup all off of db_connections
	#  Note: dbconnection_read is for doing SELECT queries only, while dbconnection_write is for doing transactions
	my $DB_name = $Foswiki::cfg{Store}{DBI}{database_name};
	my $DB_host = $Foswiki::cfg{Store}{DBI}{database_host};
	my $DB_user = $Foswiki::cfg{Store}{DBI}{database_user};
	my $DB_pwd = $Foswiki::cfg{Store}{DBI}{database_password};	
	my $dbconnection = DBI->connect("dbi:Pg:dbname=$DB_name;host=$DB_host",$DB_user,$DB_pwd, {'RaiseError' => 1}) or return "DB Death!";
	$dbconnection->{AutoCommit} = 0;  # disable transactions
	return $dbconnection;
}

# database connection
sub database_connection {
	my $this = shift;
	if($this->{database_connection}){
		return $this->{database_connection};
	}
	else{
		$this->{database_connection} = startNewdbiconnection();
		return $this->{database_connection};
	}
}

# no arguments
sub cginew {
	my ( $class ) = shift;
	#my $site_name = shift || $Foswiki::cfg{Store}{DBI}{site_name}; # dangerous?!?!?
	my $site_name = shift;
	my $site_key = '';



	# set the dbi connection
	my $dbconnection = startNewdbiconnection();

	# set the class variables

	my $this = { database_connection => $dbconnection,
			database_tables => $handlerTables, site_key => $site_key, topic_cache => {},link_cache => {},
				web_cache => {},attachment_cache => {}, user_cache => {}, group_cache => {}, site_cache =>{}, hunter => {}, conversion_table => {} };

	# setup Memcache
	$this->{memcached_connection} = new Cache::Memcached {
		'servers' => [ $Foswiki::cfg{Store}{DBI}{memcached_servers} ],
		'debug' => 0,
		'compress_threshold' => 10_000,
	};

	# bless the internal variables of the class
	bless $this, $class;
	
	my ($siteweb1,$site1) = ($this->{database_tables}->{Webs},$this->{database_tables}->{Sites});
	# get the site key and list of webs
	my $selectStatement_site = qq/SELECT 
  w1."key" as web_key, w1.current_web_name, w1.site_key, w1.web_preferences, w1.web_home, s1.current_site_name, s1.local_preferences, s1.default_preferences,
  s1.site_home, s1.admin_user, s1.admin_group, s1.system_web, s1.trash_web, s1.home_web, s1.guest_user
FROM 
  $site1 s1 INNER JOIN $siteweb1 w1 ON s1."key" = w1.site_key
WHERE 
  s1.current_site_name = ? ;/;
	my $selectHandler_site = $dbconnection->prepare($selectStatement_site);
	$selectHandler_site->execute($site_name);
	my @returnCol01 = ('web_key', 'current_web_name', 'site_key', 'web_preferences', 'web_home', 'current_site_name', 'local_preferences', 'default_preferences',
  'site_home', 'admin_user', 'admin_group', 'system_web', 'trash_web', 'home_web', 'guest_user');
	my $alreadySiteDone = 0;

	while (my $rowref = $selectHandler_site->fetchrow_arrayref) {
		my %returnhash22;
		my $k = 0;
		foreach my $rCol1 (@returnCol01){
			$returnhash22{$rCol1} = $rowref->[$k];
			$k++;
		}
		$this->{site_key} = $returnhash22{'site_key'};
		
		
		# cache site stuff
		unless($alreadySiteDone){
			$this->{site_key} = $returnhash22{'site_key'};
			$this->{site_cache} = { site_name => $returnhash22{'current_site_name'}, local_preferences => $returnhash22{'local_preferences'}, 
				default_preferences => $returnhash22{'default_preferences'}, site_home => $returnhash22{'site_home'}, 
				admin_user => $returnhash22{'admin_user'}, admin_group => $returnhash22{'admin_group'}, 
				system_web => $returnhash22{'system_web'}, trash_web => $returnhash22{'trash_web'}, home_web => $returnhash22{'home_web'},
				guest_user => $returnhash22{'guest_user'}
			};
			$alreadySiteDone = 1;
			
			# put the site by directly calling the memcache functions
			# cache for 8 hours
			#$this->memcached->set($site_name, $this->{site_key},60*60*8);
			#$this->memcached->set($this->{site_key}, $this->{site_cache});
		}
		# cache web stuff
		$this->{web_cache}->{$returnhash22{'current_web_name'}} = $returnhash22{'web_key'};
		$this->{web_cache}->{$returnhash22{'web_key'}} = { web_key => $returnhash22{'web_key'}, key => $returnhash22{'web_key'}, 
				current_web_name => $returnhash22{'current_web_name'}, site_key => $returnhash22{'site_key'}, web_preferences => $returnhash22{'web_preferences'},
				web_home => $returnhash22{'web_home'}, web_name => $returnhash22{'current_web_name'}
		};
	}
	$site_key = $this->{site_key};
	return undef unless $site_key;


	# load some hunter statements (used to find web,topic,attachment keys)
	my $Webs = $this->{database_tables}->{Webs};
	my $Topics = $this->{database_tables}->{Topics};
	my $Attachments = $this->{database_tables}->{Attachments};

	my $web_hunter = qq/SELECT $Webs."key" FROM $Webs WHERE $Webs.site_key = '$site_key' AND $Webs.current_web_name = ? /;
	my $topic_hunter = qq/SELECT $Topics."key" FROM $Topics WHERE $Topics.current_web_key = ($web_hunter) AND $Topics.current_topic_name = ? /;
	my $attachment_hunter = qq/SELECT $Attachments."key" FROM $Attachments WHERE $Attachments.current_topic_key = ($topic_hunter) AND $Attachments.current_attachment_name = ? /;


	$this->{hunter}->{web_hunter} = $web_hunter; # 1-web_name
	$this->{hunter}->{topic_hunter} = $topic_hunter; # 1-web_name, 2-topic_name
	$this->{hunter}->{attachment_hunter} = $attachment_hunter; # 1-web_name, 2-topic_name, 3-attachment_name


	# put in some column lists
	my @topic_field = ('key','link_to_latest','current_web_key','current_topic_name');
	$this->{Column_Names}->{Topics} = \@topic_field;
	my @th_field = ('key','topic_key','user_key','revision','web_key','timestamp_epoch','topic_content_key','topic_name_key','topic_content','topic_name');
	$this->{Column_Names}->{Topic_History} = \@th_field;
	my @attachment_field = ('key','link_to_latest','current_topic_key','current_attachment_name');
	$this->{Column_Names}->{Attachments} = \@attachment_field;

	my @ah_field = ('key', 'topic_key', 'version', 'path', 'timestamp_epoch', 'user_key', 'attr', 'file_name', 'file_type', 
  					'blob_store_key', 'file_store_key', 'comment', 'attachment_key', 'size', 'file_blob');
	$this->{Column_Names}->{Attachment_History} = \@ah_field;

	
	#print "creating Handler\n";
	return $this;

}

sub new {
	my $ref = ref($Foswiki::cfg{DBIStoreContribSiteHandler});

	return $Foswiki::cfg{DBIStoreContribSiteHandler};
}
sub DESTROY {
	my $this = shift;
	$this->finish();
}
# Note to developers; please undef *all* fields in the object explicitly,
# whether they are references or not. That way this method is "golden
# documentation" of the live fields in the object.
sub finish {
    my $this = shift;
    $this->cleanUpSQL() if $this->{database_connection};
    $this->{database_connection}->disconnect if $this->{database_connection};
    undef $this->{database_connection};
    undef $this->{database_tables};
    undef $this->{site_key};
}

# This rolls back any ongoing transactions before the connection is closed
sub cleanUpSQL {
	my $this = shift;
	$this->{database_connection}->rollback;
}

sub memcached {
	my $this = shift;
	return $this->{'memcached_connection'};	
}
# we have to becareful that we include the site_key in Memcache searches
# so , let's define fetch and put for memcache which automatically includes the site key
# 'topic_cache',$key => $value
sub fetchMemcached {
	my ($this,$cache,$key) = @_;
	# sets the memcache key to ($site_key.'topic_cache'.$key)
	# the key size limit is 250 characters? or bytes
	return $this->memcached->get($this->getSiteKey().$cache.$key);
}
# putMemcached($cache,$key,$value,$expiration_time) => no return, just writes Memcached
sub putMemcached {
	my ($this,$cache,$key,$value,$expiration_time) = @_;
	return undef unless $cache && $key && $value;
	# sets the memcache key to ($site_key.'topic_cache'.$key) with $expiration_time in seconds from insertion
	# the key size limit is 250 characters? or bytes
	return $this->memcached->set($this->getSiteKey().$cache.$key, $value,$expiration_time) if $expiration_time;
	return $this->memcached->set($this->getSiteKey().$cache.$key, $value) unless $expiration_time;
}


# Used in subclasses for late initialisation during object creation
# (after the object is blessed into the subclass)
sub init {
    my $this = shift;
}

# this will return the site_key
sub getSiteKey{
	my $this = shift;
	return $this->{site_key};
}
# this will return the site_key
sub getSiteName{
	my $this = shift;
	return $this->{site_cache}->{site_name};
}
# ($web_name)-> $web_key
sub getWebKey{
	my $this = shift;
	my $web_name = shift;
	return $this->{web_cache}->{$web_name};
}
# ($web_key)-> current_web_name
sub getWebName {
	my $this = shift;
	my $web_key = shift;
	return $this->{web_cache}->{$web_key}->{web_name};
}
# Return reference to list of column names
sub getColumnNameList {
	my $this = shift;
	my $column_name = shift;
	return undef unless $column_name;
	return $this->{Column_Names}->{$column_name};
}
# Return Table names
sub getTableName {
	my $this = shift;
	my $table_name = shift;
	return undef unless $table_name;
	return $handlerTables->{$table_name};
}

# do an insert into the Blob_Store
# does not commit, only execute!
# Insert Blob Store
sub insert_Blob_Store {
	my ($this,$blob_value) = @_;
	return undef unless $blob_value;
	# before doing string manipulations, decode
	my $perlblob_value = decode("UTF8", $blob_value);
	my $site_key = $this->{site_key};
	# this is used when doing searches
	my $summary = substr( $perlblob_value, 0, 150);
	my $Blob_Store = $this->{database_tables}->{Blob_Store};
	my $insertStatement_blob = qq/INSERT INTO $Blob_Store ("key", "value", value_vector, summary, number_vector) SELECT ? as "key",? as "value",
			to_tsvector('foswiki.all_languages',?) as value_vector,? as summary, ? as number_vector
		WHERE NOT EXISTS (SELECT 1 FROM $Blob_Store WHERE $Blob_Store."key" = ?);/; # 1-key, 2-value, 3-value, 4-summary, 5-number_vector, 6-key
	my $insertHandler_blob = $this->{database_connection}->prepare($insertStatement_blob);
	$insertHandler_blob->{RaiseError} = 1;	
	my $blob_key = sha1($blob_value);
	$insertHandler_blob->bind_param( 1, $blob_key, { pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler_blob->bind_param( 2, $blob_value);
	$insertHandler_blob->bind_param( 3, $blob_value);
	# need to re encode summary before stuffing it in the db
	$summary = encode("UTF8", $summary);
	$insertHandler_blob->bind_param( 4, $summary);
	# get the numerical representation of the blob_key
	my $number_vector = $this->regex_blob_number_vector($blob_value);
	$insertHandler_blob->bind_param( 5, $number_vector);
	$insertHandler_blob->bind_param( 6, $blob_key, { pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler_blob->execute;
	
	# as we put it in the db, let us also put it in Memcached
	$this->putMemcached('topic_cache',$blob_key,$blob_value);
	$this->putMemcached('topic_cache',$blob_key.'summary',$summary);
	$this->putMemcached('topic_cache',$blob_key.'number_vector',$number_vector);
	
	return $blob_key;
}
# used for guessing the number value of a blob value
sub regex_blob_number_vector {
	my ($this,$blob_value) = @_;
	my $number_vector;
	# check if the blob is a date
	if($blob_value =~ m/^\s*([12]\d{3})[-\/]([012]\d|3[01])[-\/]([012]\d|3[01])\s*([012]?\d:[0-5]\d(:[0-5]\d)?)?\s*$/){
		require Foswiki::Time;
		$number_vector = Foswiki::Time::parseTime($blob_value);
	}
	# check if it is just a number (in US format, not EU format with the decimal point being a '.')
	elsif( $blob_value =~ m/^\s*[\d,.]+\s*$/){
		$number_vector = $blob_value;
		# get rid of commas
		$number_vector =~ s/,//g;
	}	
	return $number_vector;
}
# fetch Blob Value (@array_of_keys) -> %hash_of key=>value pairs
sub get_blob_value{
	#print "Get Blob Values()\n";
	my $this = shift;
	my @key_array = @_;
	#my @question_array;
	my %cache_hash;
	my $xhash = {};
	$xhash->{'max'} = scalar(@key_array);
	return undef if $xhash->{'max'} == 0;
	my %question_hash;
	for (my $count=0; $count<scalar(@key_array); $count++)
	{
		# use this opportunity to see if the blob_values are in memcache
		my $temp_cache_value = $this->fetchMemcached('topic_cache',$key_array[$count]);
		# add the value to the cache_hash only if a value exists
		$cache_hash{$key_array[$count]} = $temp_cache_value if $temp_cache_value;
		
		# if not in memcache, then we need to fetch from the db
		$question_hash{$key_array[$count]} = '?';
		#push(@question_array,'?') unless $cache_hash{$key_array[$count]};
	}
	# check to see if all of the requested keys have corresponding values in the cache
	if(scalar @key_array == scalar (keys %cache_hash) ){
		# return the values in cache_hash
		return \%cache_hash;
	}
	
	#my $question_string = join(',',@question_array);
	my $question_string = join(',',values %question_hash);
	my $Blob_Store = $this->{database_tables}->{Blob_Store};
	my $selectStatement_bs = qq/SELECT $Blob_Store."key",$Blob_Store."value" FROM $Blob_Store WHERE $Blob_Store."key" IN ($question_string);/;

	my $selectHandler_bs = $this->{database_connection}->prepare($selectStatement_bs);
	my $count = 1;
	for my $question_hash_key ( keys %question_hash ) {
		$selectHandler_bs->bind_param( $count, $question_hash_key,{ pg_type => DBD::Pg::PG_BYTEA });
		$count += 1;
	}
	$selectHandler_bs->execute;
	my $num_rows = $selectHandler_bs->rows();
	while (my $ref = $selectHandler_bs->fetchrow_arrayref()) {
		my @row = @{$ref};
		# key => value is returned
		$xhash->{$row[0]} = $row[1];
		$this->putMemcached('topic_cache',$row[0],$row[1]);
	}
	foreach my $db_fetched (keys %{$xhash}){
		$cache_hash{$db_fetched} = $xhash->{$db_fetched};
	}
	return \%cache_hash;
}
# return UUID string
sub createUUID {
	my $this = shift;
	my $ug = new Data::UUID;
	my $uuid = $ug->create();		
	return $ug->to_string( $uuid );
}
# don't need $handler obj to generate UUID
sub generateUUID {
	my $ug = new Data::UUID;
	my $uuid = $ug->create();		
	return $ug->to_string( $uuid );	
}

# Set constraints to deferred
sub set_to_deferred {
	my ($this) = @_;
	my $deferStatement = "SET CONSTRAINTS ALL DEFERRED;";
	my $deferHandler = $this->{database_connection}->prepare($deferStatement);
	$deferHandler->execute;
}

## handling strings
# Perl trim function to remove whitespace from the start and end of the string
sub trim
{
	my $this = shift;
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
# Left trim function to remove leading whitespace
sub ltrim
{
	my $this = shift;
	my $string = shift;
	$string =~ s/^\s+//;
	return $string;
}
# Right trim function to remove trailing whitespace
sub rtrim
{
	my $this = shift;
	my $string = shift;
	$string =~ s/\s+$//;
	return $string;
}

# Check UUID with a regex
sub checkUUID {
	my $this = shift;
	my $uuid = shift;
	return undef unless $uuid =~ "^(\{{0,1}([0-9a-fA-F]){8}-([0-9a-fA-F]){4}-([0-9a-fA-F]){4}-([0-9a-fA-F]){4}-([0-9a-fA-F]){12}\}{0,1})\$";
	return $uuid;
}

sub getVirtualHostConfig {
	my $this = shift;
### Loading the configuration ###
=pod
$Foswiki::cfg{SiteName}
$Foswiki::cfg{DefaultUserLogin} = 'guest';
$Foswiki::cfg{DefaultUserWikiName} = 'cc603bdf-e112-44a8-9de1-211ed92b2802';
$Foswiki::cfg{AdminUserLogin} = 'admin';
$Foswiki::cfg{AdminUserWikiName} = '9f42b3df-63e4-460f-85cd-4355d9b5032b';
$Foswiki::cfg{SuperAdminGroup} = 'AdminGroup';<- group_key
$Foswiki::cfg{WebMasterEmail}    || 'email not set',
$Foswiki::cfg{Password},

$Foswiki::cfg{SystemWebName} = 'System';
$Foswiki::cfg{TrashWebName} = 'Trash';
$Foswiki::cfg{SitePrefsTopicName} = 'DefaultPreferences';
$Foswiki::cfg{LocalSitePreferences} = '$Foswiki::cfg{UsersWebName}.SitePreferences';
$Foswiki::cfg{HomeTopicName} = 'WebHome';
$Foswiki::cfg{WebPrefsTopicName} = 'WebPreferences';
$Foswiki::cfg{UsersWebName} = 'Main';
=cut
	my %foswikicfg;
	require  Foswiki::Contrib::DBIStoreContrib::UserHandler;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this);
	# WikiGuest login and user_key
	$foswikicfg{DefaultUserKey} = $this->{site_cache}->{guest_user};
	$foswikicfg{DefaultUserLogin} = $user_handler->getLoginName_User($foswikicfg{DefaultUserKey});
	$foswikicfg{DefaultUserWikiName} = $user_handler->getWikiName_User($foswikicfg{DefaultUserKey});
	# Admin User login and user_key
	$foswikicfg{AdminUserKey} = $this->{site_cache}->{admin_user};
	$foswikicfg{AdminUserLogin} = $user_handler->getLoginName_User($foswikicfg{AdminUserKey});
	$foswikicfg{AdminUserWikiName} = $user_handler->getWikiName_User($foswikicfg{AdminUserKey});
	# Admin Group key only
	$foswikicfg{SuperAdminGroupKey} = $this->{site_cache}->{admin_group};
	$foswikicfg{SuperAdminGroup} = $user_handler->getWikiName_User($foswikicfg{SuperAdminGroupKey});
	## Webs ##
	# 'System'
	$foswikicfg{SystemWebNameKey} = $this->{site_cache}->{system_web};
	$foswikicfg{SystemWebName} = $this->{web_cache}->{$foswikicfg{SystemWebNameKey}}->{current_web_name} || 'System';
	# 'Trash'
	$foswikicfg{TrashWebNameKey} = $this->{site_cache}->{trash_web};
	$foswikicfg{TrashWebName} = $this->{web_cache}->{$foswikicfg{TrashWebNameKey}}->{current_web_name} || 'Trash';
	# 'Main'
	$foswikicfg{UsersWebNameKey} = $this->{site_cache}->{home_web};
	$foswikicfg{UsersWebName} = $this->{web_cache}->{$foswikicfg{UsersWebNameKey}}->{current_web_name} || 'Main';
	
	## Topics ##
	# no need to change this, it is specific to each web
	$foswikicfg{WebPrefsTopicName} = 'WebPreferences'; 
	# Site Default Preferences
	$foswikicfg{SitePrefsTopicNameKey} = $this->{site_cache}->{default_preferences};
	$foswikicfg{SitePrefsTopicName} = 'System.DefaultPreferences';
	# Actual Site Preferences
	$foswikicfg{LocalSitePreferencesKey} = $this->{site_cache}->{local_preferences}; 
	$foswikicfg{LocalSitePreferences} = 'Main.SitePreferences';
	# Home Topic (most likely Main.WebHome)
	$foswikicfg{HomeTopicNameKey} = $this->{web_cache}->{$foswikicfg{UsersWebNameKey}}->{web_home};
	$foswikicfg{HomeTopicName} = 'WebHome';

	# rebless to prevent problems later
	bless $this, *Foswiki::Contrib::DBIStoreContrib::Handler;
	return \%foswikicfg;
	
}

sub s3 {
	my $this = shift;
	return $this->{_s3} if $this->{_s3};
	require Foswiki::Contrib::DBIStoreContrib::AmazonS3;
	$this->{_s3} = Foswiki::Contrib::DBIStoreContrib::AmazonS3::->new($this->getSiteKey());
	return $this->{_s3};
}
	
1;

__END__


--+ for converting form fields into epoch time

UPDATE foswiki."Blob_Store" 
SET number_vector = (SELECT EXTRACT( EPOCH FROM cast("value" AS timestamp WITH TIME ZONE) - timestamp '1970-01-01 00:00:00-00'))
WHERE "value" ~ '^\s*([12]\d{3})[-/]([012]\d|3[01])[-/]([012]\d|3[01])\s*([012]?\d:[0-5]\d)?\s*$'

---+ convert decimal numbers to the numeric data type
UPDATE foswiki."Blob_Store" 
SET number_vector = (SELECT cast(regexp_replace("value", ',', '') as numeric))
WHERE "value" ~ '^\s*[\d,.]+\s*$'


