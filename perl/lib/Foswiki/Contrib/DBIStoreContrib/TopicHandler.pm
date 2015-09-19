# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::TopicHandler;

use strict;
use warnings;

#use Exporter 'import';
#@EXPORT_OK = qw(LoadTopicRow); # symbols to export on request

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
use Digest::SHA qw(sha256_hex);
use File::Slurp qw(write_file);
use DBI qw(:sql_types);
use File::Basename				();
use Foswiki::Contrib::DBIStoreContrib::ResultSet ();
use base ("Foswiki::Contrib::DBIStoreContrib::Handler");

############################################################################################
########################              Constructors             #############################
############################################################################################


# same arg as Handler->new();
sub new {
	return shift->SUPER::new(@_);
}
# (Handler object) -> TopicHandler Object

sub init {
	# TODO:check that the argument is a handler object First!
	# blah........
	my $class = shift;
	my $this = shift;
	return bless($this,$class);
}

############################################################################################
########################            Fetching Functions         #############################
############################################################################################
=pod
	$this->putTopicKeyByWT($web_name,$topic_name,$th_topic_key);
	# ($web,$topic,$version) -> topic_history_key
	$this->putTHKeyByWTR($web_name,$topic_name,$th_revision,$th_key) if $th_revision; # for revision
	$this->putTHKeyByWTR($web_name,$topic_name,undef,$th_key) unless $version; # for link to latest
	# Sets  ($th_key) -> Topic_History.* row mapping
	$this->putTHRowByTHKey($th_key,$row_data);
$this->{topic_cache}->{$th_key} = $th_row
$this->{topic_cache}->{$th_key.'included'} = sections (STARTSECTION/ENDSECTION)
$this->{topic_cache}->{$topic_key.$revision} = $th_key
$this->{topic_cache}->{$topic_key} = $topic_row
$this->{topic_cache}->{$web.'&'.$topic} = $topic_key


$this->{include_cache} ??? in the INCLUDE macro code

=cut


# ($web, $topic) -> $topic_key mapping
sub fetchTopicKeyByWT {
	my ($this,$web_name,$topic_name) = @_;
	#print "topichandler::fetchTopicKeyByWT()\n";
	my $WTpair =  join('&',$web_name,$topic_name);
	my $topic_key = $this->{topic_cache}->{$WTpair};
	
	
	# else, we have to check memcache
	if(!$topic_key){
		$topic_key = $this->fetchMemcached('topic_cache',$WTpair);
	}

	return $topic_key;
	
}

# ($topic_key) -> Topics.* row mapping
sub fetchTopicRowByTopicKey {
	my ($this,$topic_key) = @_;

	my $topic_row_ref = {};
	$topic_row_ref = $this->{topic_cache}->{$topic_key};
	# this should return a anonymous hash with the row info intact	
	return $topic_row_ref if $topic_row_ref->{key};

	# else, we have to check memcache
	my @memtext = split("\n\t\n",$this->fetchMemcached('topic_cache',$topic_key));
	foreach my $memtextrow (@memtext){
		next unless $memtextrow;
		my @temparray = split("\n",$memtextrow);
		$topic_row_ref->{$temparray[0]} = $temparray[1];
	}
	$this->{topic_cache}->{$topic_key} = $topic_row_ref;
	return $topic_row_ref;
}

# ($web,$topic,$version) -> topic history key
sub fetchTHKeyByWTR {
	my ($this,$web_name,$topic_name,$revision) = @_;
	$revision = '-1' unless $revision; # link_to_latest th row
	my $topic_key = $this->fetchTopicKeyByWT($web_name,$topic_name);

	my $th_key = $this->fetchTHKeyByTopicKeyRevision($topic_key,$revision);
	
	return $th_key;
}
# ($topic_key,$revision) => $th_key
sub fetchTHKeyByTopicKeyRevision {
	my ($this,$topic_key,$revision) = @_;
	
	if(defined $topic_key && defined $revision){
		my $th_key = $this->{topic_cache}->{$topic_key.$revision};
		return $th_key if $th_key;
		
		# else, we have to check memcache
		$th_key = $this->fetchMemcached('topic_cache',$topic_key.$revision);
		return $th_key if $th_key;
	}	
	return undef;
}

# ($th_key) -> Topic_History.* row mapping
sub fetchTHRowByTHKey {
	my ($this,$th_key) = @_;
	my ($web_name,$topic_name,$revision);
	my $th_row_ref = {};
	$th_row_ref = $this->{topic_cache}->{$th_key};
#	($web_name,$topic_name,$revision) = ($this->{web_cache}->{$th_row_ref->{web_key}}->{current_web_name},
#		$th_row_ref->{topic_name},$th_row_ref->{revision});

	# check to see if all of the data has been retrieved from the database
	my $boolean = 1;
	my @fieldList = @{ $this->getColumnNameList('Topic_History') }; 
	foreach my $field_ref (@fieldList) {
		next if $field_ref eq 'topic_content'; # this info is not necessary
		$boolean = 0 if defined $th_row_ref->{$field_ref} && $th_row_ref->{$field_ref} =~ m/^\s+$/;
		$boolean = 0 unless $th_row_ref->{$field_ref};
	}
	
	# else, we have to check memcache
	if(!$boolean){
		my @memtext = split("\n\t\n",$this->fetchMemcached('topic_cache',$th_key));
		foreach my $memtextrow (@memtext){
			my @temparray = split("\n",$memtextrow);
			$th_row_ref->{$temparray[0]} = $temparray[1];
		}
	}

	# check one more time to see if the data has been retrieved from the database
	$boolean = 1;
	foreach my $field_ref (@fieldList) {
		next if $field_ref eq 'topic_content'; # this info is not necessary
		$boolean = 0 if $th_row_ref->{$field_ref} =~ m/^\s+$/;
		$boolean = 0 unless $th_row_ref->{$field_ref};
	}

	if($boolean){
		$this->{topic_cache}->{$th_key} = $th_row_ref;
		return $th_row_ref;
	}
	return undef;
}
# ($web,$topic,$version) -> Topic_History.* row mapping
sub fetchTHRowByWTR {
	my ($this,$web_name,$topic_name,$revision) = @_;
	my $th_key = $this->fetchTHKeyByWTR($web_name,$topic_name,$revision);
	return undef unless $th_key;
	my $row_data = $this->fetchTHRowByTHKey($th_key);
	return $row_data;
}
# Sets  ($th_key) -> Include Section row mapping
# if $section is null, then entire topic is stuffed
sub fetchIncludeSectionByTHKey {
	my ($this,$th_key, $section) = @_;
	my $text;
	return undef unless $th_key && $section;
	$text = $this->{topic_cache}->{$th_key}->{'included'}->{$section} if $section;
	return $text if $text;
	return $this->fetchMemcached('topic_cache',$th_key.'included'.$section);
}

############################################################################################
########################          Putting Functions            #############################
############################################################################################

# Sets ($web, $topic) -> $topic_key mapping
sub putTopicKeyByWT {
	my ($this,$web_name,$topic_name,$topic_key) = @_;
	my $WTpair =  join('&',$web_name,$topic_name) if $web_name && $topic_name;
	$this->{topic_cache}->{$WTpair} = $topic_key if $WTpair && $topic_key;
	
	# also, put this in memcache, but with a time limit of just a minute?
	# need time limit b/c 
	$this->putMemcached('topic_cache',$WTpair,$topic_key,180);
}
# Sets ($topic_key) -> Topics.* row mapping
sub putTopicRowByTopicKey {
	my ($this,$topic_key,$topic_row_ref) = @_;
	my @fieldList = ('key','link_to_latest','current_web_key','current_topic_name','current_topic_name_key');
	my @memtext;
	foreach my $field (@fieldList) {
		$this->{topic_cache}->{$topic_key}->{$field} = $topic_row_ref->{$field};
		push(@memtext,$field."\n".$topic_row_ref->{$field}) if $topic_row_ref->{$field};
	}
	$this->putMemcached('topic_cache',$topic_key,join("\n\t\n",@memtext));
}

# Sets ($web,$topic,$version) -> topic_history_key
# need to know the topic_key, before we can save the topic_history_key
sub putTHKeyByWTR {
	my ($this, $web_name, $topic_name,$revision, $th_key) = @_;
	$revision = '-1' unless $revision; # link_to_latest th row
	my $topic_key = $this->fetchTopicKeyByWT($web_name,$topic_name);
	#my $WTR =  join('&',$web_name,$topic_name,$revision) if $web_name && $topic_name;
	$this->{topic_cache}->{$topic_key.$revision} = $th_key if $topic_key && $th_key;
	$this->putMemcached('topic_cache',$topic_key.$revision,$th_key) if $topic_key && $th_key;
}

# Sets  ($th_key) -> Topic_History.* row mapping
sub putTHRowByTHKey {
	my ($this,$th_key,$th_ref) = @_;

	my @fieldList = ('key','topic_key','user_key','revision','web_key','timestamp_epoch','topic_content_key','topic_name_key','topic_content','topic_name');
	my @memtext;
	foreach my $field (@fieldList){
		$this->{topic_cache}->{$th_key}->{$field} = $th_ref->{$field};
		push(@memtext,$field."\n".$th_ref->{$field}) if $th_ref->{$field};
	}
	# must put th_ref into text form
	$this->putMemcached('topic_cache',$th_key,join("\n\t\n",@memtext));
	
}

# Sets  ($th_key) -> Include Section row mapping
sub putIncludeSectionByTHKey {
	my ($this,$th_key, $section, $text) = @_;
	$this->{topic_cache}->{$th_key}->{'included'}->{$section} = $text;
	$this->putMemcached('topic_cache',$th_key.'included'.$section,$text);
}
###############################
#### Translating Functions ####
###############################
## load Conversion Table

=pod
---+++ LoadConversionTable()-> returnhash->{'mpName'}->{'from'} = WT;  or ->{'to'} = Topics/Users/etc...
This loads the preferences which get converted to either a Topic, User, Group, etc upon Topic save.

=cut

sub LoadConversionTable {
	my ($this,) = @_;
	my $returnHash;
	# first, check if the site prefs have been put into the Handler hash
	if(scalar( keys %{$this->{conversion_table}} ) > 0){
		return $this->{conversion_table};
	}
	# first, check if the site prefs have been put into the Memcached cache
	my $returnCacheText = $this->fetchMemcached('preference_cache','conversion_table');
	if($returnCacheText){
		
		my @returnCacheArray = split("\n\n",$returnCacheText);
		foreach my $NameValuePair (@returnCacheArray){
			my @namevaluearray = split("\n",$NameValuePair);
			$returnHash->{$namevaluearray[0]}->{'from'} = $namevaluearray[1];
			$returnHash->{$namevaluearray[0]}->{'to'} = $namevaluearray[2];
		}
		$this->{conversion_table} = $returnHash;
		return $returnHash;
	}
	
	my $MPD = $this->getTableName('Meta_Preferences_DataTypes');
	my $selectStatement = qq{
SELECT 
  mpd.name, 
  mpd."from", 
  mpd."to"
FROM 
  $MPD mpd
WHERE mpd.from IS NOT NULL

};
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute();
	my ($mpname,$mpfrom,$mpto);
	$selectHandler->bind_col( 1, \$mpname );
	$selectHandler->bind_col( 2, \$mpfrom );
	$selectHandler->bind_col( 3, \$mpto );
	
	my @mpArray;
	my $returnHash;
	while ($selectHandler->fetch) {
		$returnHash->{$mpname}->{'from'} = $mpfrom;
		$returnHash->{$mpname}->{'to'} = $mpto;
		push(@mpArray,$mpname."\n".$mpfrom."\n".$mpto);
	}
	my $mpCacheText = join("\n\n",@mpArray);
	$this->putMemcached('preference_cache','conversion_table',$mpCacheText);
	$this->{conversion_table} = $returnHash;
	return $returnHash;
}
# ($type, $name, $value, 'in') -> $value_key for 'in'
# ($type, $name, $value_key, 'out') -> $value for 'out'
sub convert_MP {
	my $this = shift;
	$this->LoadConversionTable();
	my ($type,$name,$valueQ,$direction) = @_;
	return undef unless $name && $valueQ;
	# strip spaces from $valueQ
	$valueQ = $this->trim($valueQ);
	my ($from,$toS) = ($this->{conversion_table}->{$name}->{from},$this->{conversion_table}->{$name}->{to});
	return $this->convert_Var($from,$toS,$valueQ,$direction);
}
# ($from, $to, $value, 'in') -> $value_key for 'in'
# ($from, $to, $value_key, 'out') -> $value for 'out'
# by default, original value is returned
sub convert_Var {
	my $this = shift;
	my ($from, $toS, $valueQ, $direction) = @_;
	return $valueQ unless $from && $toS && $direction;
	#die "All variables ($from, $toS, $valueQ, $direction)" if $toS;
	my @TSs = split(',',$toS);
	foreach my $to (@TSs){
		my $method = 'Foswiki::Contrib::DBIStoreContrib::TopicHandler::_convert_'.$from.'_'.$to.'_'.$direction;

		if ( defined &$method ) {
			no strict 'refs';
			my $answer = &$method($this,$valueQ); 
			# possible issues with arrays being returned as array references
			return $answer if $answer;
        }
	}
	return $valueQ;
} 
# web => web_key
sub _convert_W_Webs_in {
	my $this = shift;
	my $web_name = shift;
	return $this->{web_cache}->{$web_name};
}
# web_key => web
sub _convert_W_Webs_out {
	my $this = shift;
	my $web_key = shift;
	return $this->{web_cache}->{$web_key}->{current_web_name};
}

# "web.topic" => topic_key
sub _convert_WT_Topics_in {
	my $this = shift;
	my $valueQ = shift;
	my $web_in_url = $Foswiki::Plugins::SESSION->{'webName'};
	my ($web_name,$topic_name) = Foswiki::Func::normalizeWebTopicName($web_in_url,$valueQ);
	return undef unless $web_name && $topic_name;
	my $topic_key = $this->fetchTopicKeyByWT($web_name,$topic_name);
	return $topic_key if $topic_key;
	
	my $site_key = $this->{site_key};
	my $bytea_topic_name = sha1($topic_name);

	my $Webs = $this->getTableName('Webs');
	my $Topics = $this->getTableName('Topics');
	my $selectStatement = qq/SELECT 
t1."key" AS topic_key
FROM 
  $Topics t1 INNER JOIN $Webs w1 ON t1.current_web_key = w1."key"
WHERE 
  w1.site_key = '$site_key' 
  AND w1.current_web_name = ?
  AND t1.current_topic_name = ?;/; # 1-web_name, 2-bytea_topic_name
  	my $selectHandler = $this->database_connection()->prepare($selectStatement);
  	$selectHandler->bind_param( 1, $web_name );
  	$selectHandler->bind_param( 2, $bytea_topic_name,{ pg_type => DBD::Pg::PG_BYTEA });
	
	$selectHandler->execute;
	

	$selectHandler->bind_col( 1, \$topic_key );
	while ($selectHandler->fetch) {
		$this->putTopicKeyByWT($web_name,$topic_name,$topic_key);
		return $topic_key;
	}
	
	return undef;
}

# topic_key => (web,topic)
sub _convert_WT_Topics_out {
	my $this = shift;
	my $topic_key = shift;
	return undef unless defined $topic_key;

	# check cache first
	# forget about caching, causes weird issues....
#	my $thkey9 = $this->fetchTHKeyByTopicKeyRevision($topic_key);
#	my @wt001 = $this->LoadWTRFromTHKey($thkey9);
#if($topic_key eq 'd8902db4-9e44-4292-86b6-1a807b981310'){
#	die "$topic_key:($thkey9)(@wt001)";
#	}
#	return \@wt001;
	
	
	my $BS = $this->getTableName('Blob_Store');
	my $Webs = $this->getTableName('Webs');
	my $Topics = $this->getTableName('Topics');
	my $selectStatement = qq/SELECT 
  w1.current_web_name, 
  tname."value"
FROM 
  $Topics t1
	INNER JOIN $Webs w1 ON w1."key" = t1.current_web_key
	INNER JOIN $BS tname ON tname."key" = t1.current_topic_name
WHERE 
  t1."key" = ? ;/;
  
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($topic_key);
	my ($web_name,$topic_name);
	$selectHandler->bind_col( 1, \$web_name );
	$selectHandler->bind_col( 2, \$topic_name );
	while ($selectHandler->fetch) {
		$this->putTopicKeyByWT($web_name,$topic_name,$topic_key);
		my @wt002 = ($web_name,$topic_name); 
		return \@wt002;
	}
	return undef;
}
# (web,topic) => group_key 
sub _convert_WT_Groups_in {
	my $this = shift;
	my $valueQ = shift;
	my $web_in_url = $Foswiki::Plugins::SESSION->{'webName'};
	my ($web_name,$topic_name) = Foswiki::Func::normalizeWebTopicName($web_in_url,$valueQ);
	my $group_key = $this->{group_cache}->{join('&',$web_name,$topic_name)};
	return $group_key if $group_key;
	my $site_key = $this->{site_key};
	my $bytea_topic_name = sha1($topic_name);
	my $web_key = $this->{web_cache}->{$web_name};
	return undef unless $web_key;
	
	my $Groups = $this->getTableName('Groups');
	my $Topics = $this->getTableName('Topics');
	my $selectStatement = qq/SELECT g1."key"
FROM 
$Topics t1 
	INNER JOIN $Groups g1 ON g1.group_topic_key = t1."key"
WHERE 
  t1.current_web_key = '$web_key' AND t1.current_topic_name = ? ;/; # 1-bytea_topic_name
  
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->bind_param( 1, $bytea_topic_name, { pg_type => DBD::Pg::PG_BYTEA });
	$selectHandler->execute();
	
	$selectHandler->bind_col( 1, \$group_key );
	while ($selectHandler->fetch) {
		$this->{group_cache}->{join('&',$web_name,$topic_name)} = $group_key;
		return $group_key;
	}
	return undef;
}
# group_key => (web,topic)
sub _convert_WT_Groups_out {
	my $this = shift;
	my ($group_key) = @_;
	return undef unless $group_key;
	my $BS = $this->getTableName('Blob_Store');
	my $Webs = $this->getTableName('Webs');
	my $Topics = $this->getTableName('Topics');
	my $Groups = $this->getTableName('Groups');
	my $selectStatement = qq/SELECT w1.current_web_name, tname."value"
FROM 
  $Topics t1
	INNER JOIN $Groups g1 ON t1."key" = g1.group_topic_key
	INNER JOIN $Webs w1 ON t1.current_web_key = w1."key"
	INNER JOIN $BS tname ON t1.current_topic_name = tname."key"
WHERE 
  g1."key" = ? ;/;
  
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($group_key);
	my ($web_name,$topic_name);
	$selectHandler->bind_col( 1, \$web_name );
	$selectHandler->bind_col( 2, \$topic_name );
	while ($selectHandler->fetch) {
		$this->{group_cache}->{join('&',$web_name,$topic_name)} = $group_key;
		my @wt002 = ($web_name,$topic_name); 
		return \@wt002;
	}
	return undef;
}

# (web,topic) => user_key 
sub _convert_WT_Users_in {
	my $this = shift;
	my $valueQ = shift;
	my $web_in_url = $Foswiki::Plugins::SESSION->{'webName'};
	my ($web_name,$topic_name) = Foswiki::Func::normalizeWebTopicName($web_in_url,$valueQ);
	my $user_key = $this->{user_cache}->{join('&',$web_name,$topic_name)};
	return $user_key if $user_key;
	my $site_key = $this->{site_key};
	my $bytea_topic_name = sha1($topic_name);
	my $web_key = $this->{web_cache}->{$web_name};
	return undef unless $web_key;
	
	my $Users = $this->getTableName('Users');
	my $Topics = $this->getTableName('Topics');
	my $selectStatement = qq/SELECT 
  u1."key"
FROM 
$Topics t1 
	INNER JOIN $Users u1 ON u1.user_topic_key = t1."key"
WHERE 
 t1.current_web_key = '$web_key' AND t1.current_topic_name = ? ;/; # 1-bytea_topic_name
  
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->bind_param( 1, $bytea_topic_name, { pg_type => DBD::Pg::PG_BYTEA });
	$selectHandler->execute();
	
	$selectHandler->bind_col( 1, \$user_key );
	while ($selectHandler->fetch) {
		$this->{user_cache}->{join('&',$web_name,$topic_name)} = $user_key;
		return $user_key;
	}
	return undef;
}
# user_key => (web,topic)
sub _convert_WT_Users_out {
	my $this = shift;
	my ($user_key) = @_;
	return undef unless $user_key;
	my $BS = $this->getTableName('Blob_Store');
	my $Webs = $this->getTableName('Webs');
	my $Topics = $this->getTableName('Topics');
	my $Users = $this->getTableName('Users');
	my $selectStatement = qq/SELECT w1.current_web_name, tname."value"
FROM 
  $Topics t1
	INNER JOIN $Users u1 ON t1."key" = u1.user_topic_key
	INNER JOIN $Webs w1 ON t1.current_web_key = w1."key"
	INNER JOIN $BS tname ON t1.current_topic_name = tname."key"
WHERE 
  u1."key" = ? ;/; # 1-user_key
  
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($user_key);
	my ($web_name,$topic_name);
	$selectHandler->bind_col( 1, \$web_name );
	$selectHandler->bind_col( 2, \$topic_name );
	while ($selectHandler->fetch) {
		$this->{user_cache}->{join('&',$web_name,$topic_name)} = $user_key;
		my @wt002 = ($web_name,$topic_name); 
		return \@wt002;
	}
	return undef;
}

# "web.topic@revision" => topic_history_key
# "Main.WebHome@3" => topic_history_key
sub _convert_WTR_Topic_History_in {
	my $this = shift;
	my $valueQ = shift;
	# 
	my ($wtpost,$revpost);
	if($valueQ =~ m/([^@]*)@+([0-9]+)/) { 
		$wtpost = $1;
		$revpost = $2;
	}
	
	my $web_in_url = $Foswiki::Plugins::SESSION->{'webName'};
	my ($web_name,$topic_name) = Foswiki::Func::normalizeWebTopicName($web_in_url,$valueQ);
	my $version = $revpost;
	return undef unless $web_name && $topic_name;
	my $topic_history_key = $this->fetchTHKeyByWTR($web_name,$topic_name,$version);
	my $row_ref = $this->LoadTHRow($web_name,$topic_name,$version);
	return $row_ref->{topic_history_key};
}

# topic_history_key => (web,topic,revision)
sub _convert_WTR_Topic_History_out {
	my $this = shift;
	return undef;
}


# local time => epoch
sub _convert_local_epoch_in {
	my $this = shift;
	my $local_time = shift;
	require Foswiki::Time;
	# assuming that the input is local time, so we added the '1' as an argument
	return Foswiki::Time::parseTime($local_time,1);
	return undef;
}

# this func will must likely be used for the topic name
# text => binary sha1
sub _convert_text_binary_in {
	my $this = shift;
	my $topic_name = shift;
	return sha1($topic_name);
}

# this func will must likely be used for the topic name
# text => binary sha1
sub _convert_text_sha1_in {
	my $this = shift;
	my $topic_name = shift;
	return sha1($topic_name);
}
############################################################################################
########################          SQL Select Functions         #############################
############################################################################################

# ($web,$topic,$revision) -> $row_data->{field} with all fields returned
sub LoadTHRow { 
	my ($this,$web_name,$topic_name,$version) = @_;
	my $site_key = $this->{site_key};
	my $bytea_topic_name = sha1($topic_name);
	#print "topichandler::LoadTHRow()\n";
	### First, check if it is already in the cache ###
	my $row_data = $this->fetchTHRowByWTR($web_name,$topic_name,$version);
	#return $row_data if $row_data->{key};

	my $boolean = 1;
	my @fieldList = @{ $this->getColumnNameList('Topic_History') }; 

	foreach my $field_ref (@fieldList) {
		next if $field_ref eq 'topic_content'; # this info is not necessary
		$boolean = 0 unless $row_data->{$field_ref};
	}
	if($boolean){
		# ($web,$topic) -> topic_key
		#$this->putTopicKeyByWT($web_name,$topic_name,$row_data->{topic_key}) unless $version;
		# ($web,$topic,$version) -> topic_history_key
		#$this->putTHKeyByWTR($web_name,$topic_name,$version,$row_data->{key}) if $version; # for revision
		#$this->putTHKeyByWTR($web_name,$topic_name,undef,$row_data->{key}) unless $version; # for link to latest
		# Sets  ($th_key) -> Topic_History.* row mapping
		#$this->putTHRowByTHKey($row_data->{key},$row_data);
		#return $row_data;
	}
	# clean out row_ref so that we can use it later
	$row_data = {};
	
	# TESTING whether something is screwy with the cache or not!!!!!!
	my ($cache_th_key,$cache_topic_key);
	$cache_topic_key = $this->{topic_cache}->{$web_name.'&'.$topic_name};
	if(!$version && defined $cache_topic_key){	
		$cache_th_key = $this->{topic_cache}->{$cache_topic_key.'-1'};
	}
	elsif(defined $cache_topic_key){
		$cache_th_key = $this->{topic_cache}->{$cache_topic_key.$version};
	}
	$row_data = $this->{topic_cache}->{$cache_th_key} if defined $cache_th_key;
	return $row_data if defined $row_data->{key};
	
	
	
	
	
	
	
	
	######## The rest is assuming the th_row is not in the cache
	# since it is a select statement, let's do autocommit
	#$this->database_connection()->{AutoCommit} = 1;
	# Name all of the database tables
	my $Webs = $this->getTableName('Webs');
	my $Topic_History = $this->getTableName('Topic_History');
	my $Topics = $this->getTableName('Topics');
	#my $topic_hunter = $this->{hunter}->{topic_hunter};
	my $BS = $this->getTableName('Blob_Store');
	my $topic_hunter = qq/SELECT t101."key" FROM $Topics t101 
			INNER JOIN $Webs w101 ON t101.current_web_key = w101."key"
			INNER JOIN $BS tname101 ON t101.current_topic_name = tname101."key"
			WHERE w101.current_web_name = ? AND tname101."value" = ?  /;# 1-web,2-topic_name


	# select part
	my $select_part = qq/SELECT th1."key", th1.topic_key, th1.user_key, th1.revision, th1.web_key, th1.timestamp_epoch, th1.topic_content, th1.topic_name, tname."value" /;
	# no version
	
	my $selectStatement_th_noVer = qq/$select_part
		FROM $Topics t1 
			INNER JOIN $Topic_History th1 ON th1."key" = t1."link_to_latest" 
			INNER JOIN $BS tname ON t1.current_topic_name = tname."key"
			INNER JOIN $Webs w1 ON t1.current_web_key = w1."key"
		WHERE w1.site_key = '$site_key' AND w1.current_web_name = ? AND t1.current_topic_name = ? ;/ unless $version;
	# version
	my $selectStatement_th_Ver = qq/$select_part
		FROM $Topics t1 
			INNER JOIN $Topic_History th1 ON th1.topic_key = t1."key" 
			INNER JOIN $BS tname ON t1.current_topic_name = tname."key"
			INNER JOIN $Webs w1 ON t1.current_web_key = w1."key"
		WHERE w1.site_key = '$site_key' AND w1.current_web_name = ? AND t1.current_topic_name = ? AND th1.revision = ? ;/ if $version;

	my ($topic_key,$topic_hunter_handle);
	if($version){
		# 1-web_name, 2-topic_name, 3-revision
		$topic_hunter_handle = $this->database_connection()->prepare($selectStatement_th_Ver);
		$topic_hunter_handle->bind_param( 1, $web_name);
		$topic_hunter_handle->bind_param( 2, $bytea_topic_name, { pg_type => DBD::Pg::PG_BYTEA });
		$topic_hunter_handle->bind_param( 3, $version);
		$topic_hunter_handle->execute;	
	}
	else {
		# 1-web_name, 2-topic_name
		$topic_hunter_handle = $this->database_connection()->prepare($selectStatement_th_noVer);
		$topic_hunter_handle->bind_param( 1, $web_name);
		$topic_hunter_handle->bind_param( 2, $bytea_topic_name, { pg_type => DBD::Pg::PG_BYTEA });
		$topic_hunter_handle->execute;
	}

	# fetch the row from Topics
	my %topic_hash;
	my ($th_key,$th_topic_key,$th_user_key,$th_revision,$th_web_key,$th_timestamp_epoch,$th_topic_content,$th_topic_name);
	$topic_hunter_handle->bind_col( 1, \$th_key );
	$topic_hunter_handle->bind_col( 2, \$th_topic_key );
	$topic_hunter_handle->bind_col( 3, \$th_user_key );
	$topic_hunter_handle->bind_col( 4, \$th_revision );
	$topic_hunter_handle->bind_col( 5, \$th_web_key );
	$topic_hunter_handle->bind_col( 6, \$th_timestamp_epoch );
	$topic_hunter_handle->bind_col( 7, \$th_topic_content,{ pg_type => DBD::Pg::PG_BYTEA } );
	$topic_hunter_handle->bind_col( 8, \$th_topic_name,{ pg_type => DBD::Pg::PG_BYTEA } );
	while ($topic_hunter_handle->fetch) {
		#"SELECT th1.\"key\",th1.topic_key,th1.user_key, th1.revision,th1.web_key, th1.timestamp_epoch, bs2.\"value\" ";
		$row_data->{key} = $th_key;
		$row_data->{topic_history_key} = $th_key;
		$row_data->{topic_key} = $th_topic_key;
		$row_data->{user_key} = $th_user_key;
		$row_data->{revision} = $th_revision;
		$row_data->{web_key} = $th_web_key;
		$row_data->{timestamp_epoch} = $th_timestamp_epoch;
		$row_data->{topic_content_key} = $th_topic_content;
		$row_data->{topic_name_key} = $th_topic_name;
		$row_data->{topic_name} = $topic_name;
	}
	return undef unless $th_key;
	# TESTING whether something is screwy with the cache or not!!!!!!
	if(!$version){
		$this->{topic_cache}->{$web_name.'&'.$topic_name} = $row_data->{topic_key};
		$this->{topic_cache}->{$row_data->{topic_key}.'-1'} = $row_data->{key};
	}

	$this->{topic_cache}->{$row_data->{topic_key}.$row_data->{revision}} = $row_data->{key};
	$this->{topic_cache}->{$row_data->{key}} = $row_data;
	

	# Cache as much as possible
	# ($web,$topic) -> topic_key 
	$this->putTopicKeyByWT($web_name,$topic_name,$th_topic_key) unless $version;
	# ($web,$topic,$version) -> topic_history_key
	$this->putTHKeyByWTR($web_name,$topic_name,$th_revision,$th_key) if $version; # for revision
	$this->putTHKeyByWTR($web_name,$topic_name,undef,$th_key) unless $version; # for link to latest
	# Sets  ($th_key) -> Topic_History.* row mapping
	$this->putTHRowByTHKey($th_key,$row_data);

	return $row_data;
}

# (topic_key)->$web.$topic
sub LoadWTFromTopicKey {
	my ($this,$topic_key) = @_;
	
	# check memcache and local cache at the same time
	my $topic_row = $this->fetchTopicRowByTopicKey($topic_key);
	my $cache_web_name = $this->{web_cache}->{$topic_row->{current_web_key}}->{current_web_name};
	if($topic_row->{current_web_key} && $topic_row->{current_topic_name} ){
			return ($cache_web_name, $topic_row->{current_topic_name});
	}
	

	my $Webs = $this->getTableName('Webs');
	my $Topics = $this->getTableName('Topics');
	my $BS = $this->getTableName('Blob_Store');
	my $selectStatement = qq/SELECT webs.current_web_name, bs."value", topics.link_to_latest ,
	topics.current_web_key, topics.current_topic_name
				FROM $Topics topics 
					INNER JOIN $BS bs ON topics.current_topic_name = bs."key"
					INNER JOIN $Webs webs ON topics.current_web_key = webs."key"
				WHERE topics."key" = ?;/;
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($topic_key);
	my ($web_name,$topic_name, $th_key, $current_web_key,$current_topic_name_key);
	$selectHandler->bind_col( 1, \$web_name );
	$selectHandler->bind_col( 2, \$topic_name );
	$selectHandler->bind_col( 3, \$th_key );
	$selectHandler->bind_col( 4, \$current_web_key );
	$selectHandler->bind_col( 5, \$current_topic_name_key );
	while ($selectHandler->fetch) {
		$this->putTopicKeyByWT($web_name,$topic_name,$topic_key);
		$this->putTHKeyByWTR($web_name,$topic_name,'-1',$th_key);
		$this->putTopicRowByTopicKey($topic_key,{
			'key' => $topic_key,'link_to_latest' => $th_key,
			'current_web_key' => $current_web_key,'current_topic_name' => $topic_name,
			'current_topic_name_key' => $current_topic_name_key
			});
		die "Hi($web_name,$topic_name,$topic_key)" if $topic_key eq 'd8902db4-9e44-4292-86b6-1a807b981310';
		return ($web_name,$topic_name);
	}

	return undef;
}
# this fetches both the latest topic history row, and also the revision row being requested
sub LoadTHRowFromTHKey {
	my ($this,$old_th_key) = @_;
	
	# check local cache first
	return $this->{topic_cache}->{$old_th_key} if $this->{topic_cache}->{$old_th_key}->{key};
	

	my $Webs = $this->getTableName('Webs');
	my $Topics = $this->getTableName('Topics');
	my $TH = $this->getTableName('Topic_History');
	
	my $select_part = qq/
	SELECT oldth1."key", oldth1.topic_key, 
		oldth1.user_key, oldth1.revision, oldth1.web_key, 
		oldth1.timestamp_epoch, oldth1.topic_content, 
		oldth1.topic_name
	       , newth1."key", newth1.topic_key, 
		newth1.user_key, newth1.revision, newth1.web_key, 
		newth1.timestamp_epoch, newth1.topic_content, 
		newth1.topic_name
		/;
	my $selectStatement = qq/			
	$select_part
FROM
  $Topics t1 
    INNER JOIN $TH newth1 ON t1.link_to_latest = newth1."key" 
    INNER JOIN $TH oldth1 ON t1."key" = oldth1.topic_key
WHERE 
  oldth1."key" = ?
  /; # 1-old_th_key
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($old_th_key);
	my (
	   $old_key,$old_topic_key, 
	   $old_user_key,$old_revision,
	   $old_web_key,$old_timestamp_epoch,$old_topic_content_key,
	   $old_topic_name_key, $old_topic_name,
	   $new_key,$new_topic_key, 
	   $new_user_key,$new_revision,
	   $new_web_key,$new_timestamp_epoch,$new_topic_content_key,
	   $new_topic_name_key, $new_topic_name
	);
	$selectHandler->bind_col( 1, \$old_key );
	$selectHandler->bind_col( 2, \$old_topic_key );
	$selectHandler->bind_col( 3, \$old_user_key );
	$selectHandler->bind_col( 4, \$old_revision );
	$selectHandler->bind_col( 5, \$old_web_key );
	$selectHandler->bind_col( 6, \$old_timestamp_epoch );
	$selectHandler->bind_col( 7, \$old_topic_content_key );
	$selectHandler->bind_col( 8, \$old_topic_name_key );
	$selectHandler->bind_col( 9, \$new_key );
	$selectHandler->bind_col( 10, \$new_topic_key );
	$selectHandler->bind_col( 11, \$new_user_key );
	$selectHandler->bind_col( 12, \$new_revision );
	$selectHandler->bind_col( 13, \$new_web_key );
	$selectHandler->bind_col( 14, \$new_timestamp_epoch );
	$selectHandler->bind_col( 15, \$new_topic_content_key );
	$selectHandler->bind_col( 16, \$new_topic_name_key );
	my ($new_row,$old_row);
	while ($selectHandler->fetch) {
		
		$new_row = {'key' => $new_key, 'topic_key' => $new_topic_key,
		  'user_key' => $new_user_key, 'revision' => $new_revision, 'web_key' => $new_web_key,
		  'timestamp_epoch' => $new_timestamp_epoch, 'topic_content_key' => $new_topic_content_key,
		  'topic_name_key' => $new_topic_name_key, 'topic_name' => $new_topic_name};

		$this->{topic_cache}->{$new_key} = $new_row;
		$this->{topic_cache}->{$new_topic_key.'-1'} = $new_key;
		$this->{topic_cache}->{$new_topic_key.$new_revision} = $new_key;
		
		my $new_web_name = $this->{web_cache}->{$new_web_key}->{current_web_name};
		$this->{topic_cache}->{$new_web_name.'&'.$new_topic_name} = $new_topic_key;
		
		$old_row = $new_row;
		if($new_key ne $old_key){
			$old_row = {'key' => $old_key, 'topic_key' => $old_topic_key,
				'user_key' => $old_user_key, 'revision' => $old_revision, 'web_key' => $old_web_key,
				'timestamp_epoch' => $old_timestamp_epoch, 'topic_content_key' => $old_topic_content_key,
				'topic_name_key' => $old_topic_name_key, 'topic_name' => $old_topic_name};
			$this->{topic_cache}->{$old_key} = $old_row;
			$this->{topic_cache}->{$old_topic_key.$old_revision} = $old_key;
		}
		
	}
	if($new_row->{key}){
		# we need to fetch the topic names separately
		my $name_ref = $this->get_blob_value(($old_row->{topic_name_key},$new_row->{topic_name_key}));
		$old_row->{topic_name} = $name_ref->{$old_row->{topic_name_key}};
		$new_row->{topic_name} = $name_ref->{$new_row->{topic_name_key}} if $new_row->{key} ne $old_row->{key};
	}

	return $old_row;
}

# (th_key)->($web,$topic,$rev)
sub LoadWTRFromTHKey {
	my ($this,$old_th_key) = @_;

	# search the cache first
	# ...first, get old_th_row
	my $old_th_row = $this->{topic_cache}->{$old_th_key};
	# ...second, get new th_key
	my $new_th_key = $this->{topic_cache}->{$old_th_row->{topic_key}.'-1'} if defined $old_th_row->{topic_key};
	my $new_th_row = $this->{topic_cache}->{$new_th_key};
	return ($this->{web_cache}->{$new_th_row->{web_key}}->{current_web_name},$new_th_row->{topic_name}) 	if defined $new_th_row->{web_key};	
	
	# this line also loads the new th row
	$old_th_row = $this->LoadTHRowFromTHKey($old_th_key);
	$new_th_key = $this->{topic_cache}->{$old_th_row->{topic_key}.'-1'};
	$new_th_row = $this->{topic_cache}->{$new_th_key};
	return ($this->{web_cache}->{$new_th_row->{web_key}}->{current_web_name},$new_th_row->{topic_name})
		if defined $new_th_row->{key};
}

# (topic_history_key)-> list of link rows
sub LoadLinks {
	my ($this,$t_h_key) = @_;
	my %link_row;
	return undef unless $t_h_key;
	#print "Doing LoadLinks()\n";
	# Name all of the database tables
	my $Webs = $this->getTableName('Webs');
	my $Links = $this->getTableName('Links');
	my $Topic_History = $this->getTableName('Topic_History');
	my $Topics = $this->getTableName('Topics');
	my $Attachments = $this->getTableName('Attachments');
	my $Attachment_History = $this->getTableName('Attachment_History');
	my $topic_hunter = $this->{hunter}->{topic_hunter};
	my $selectStatement = qq/SELECT links."key", ah1.file_name, ah1.file_type, th1.topic_name, links.destination_attachment_history, links.destination_topic_history, 
  links.destination_attachment, links.destination_topic, links.link_type, links.blob_key, a1.current_attachment_name, t1.current_topic_name, 
  t1.current_web_key, th1.web_key
FROM $Links links
  LEFT JOIN $Topics t1 ON links.destination_topic = t1."key"
  LEFT JOIN $Topic_History th1 ON links.destination_topic_history = th1."key"
  LEFT JOIN $Attachments a1 ON links.destination_attachment = a1."key"
  LEFT JOIN $Attachment_History ah1 ON links.destination_attachment_history = ah1."key"
WHERE links.topic_history_key = ?;/;
	# 1-web_name, 2-topic_name
	my $selectHandle = $this->database_connection()->prepare($selectStatement);
	$selectHandle->execute($t_h_key);
	# fetch the links from Links

	my ($link_key,$file_name,$file_type,$th_name,$dest_ah,$dest_th,$dest_a,$dest_t,$link_type,$blob_key,$c_a_name,$c_t_name,$c_w_key,$w_key);
	$selectHandle->bind_col( 1, \$link_key );
	$selectHandle->bind_col( 2, \$file_name );
	$selectHandle->bind_col( 3, \$file_type );
	$selectHandle->bind_col( 4, \$th_name, { pg_type => DBD::Pg::PG_BYTEA });
	$selectHandle->bind_col( 5, \$dest_ah );
	$selectHandle->bind_col( 6, \$dest_th );
	$selectHandle->bind_col( 7, \$dest_a);
	$selectHandle->bind_col( 8, \$dest_t);
	$selectHandle->bind_col( 9, \$link_type);
	$selectHandle->bind_col( 10, \$blob_key,{ pg_type => DBD::Pg::PG_BYTEA });
	$selectHandle->bind_col( 11, \$c_a_name);
	$selectHandle->bind_col( 12, \$c_t_name,{ pg_type => DBD::Pg::PG_BYTEA });
	$selectHandle->bind_col( 13, \$c_w_key);
	$selectHandle->bind_col( 14, \$w_key);

	my @blobkey_list;
	while ($selectHandle->fetch) {
		#"SELECT th1.\"key\",th1.topic_key,th1.user_key, th1.revision,th1.web_key, th1.timestamp_epoch, bs2.\"value\" ";
		$link_row{$link_key}{file_name} = $file_name; # for attachments or ah
		$link_row{$link_key}{file_type} = $file_type; # for attachments or ah
		$link_row{$link_key}{th_name_key} = $th_name; # topic_history
		$link_row{$link_key}{dest_ah} = $dest_ah; # for attachment_history
		$link_row{$link_key}{dest_th} = $dest_th; # for topic_history
		$link_row{$link_key}{dest_a} = $dest_a; # for attachments
		$link_row{$link_key}{dest_t} = $dest_t; # for topics
		$link_row{$link_key}{link_type} = $link_type; # category of links
		$link_row{$link_key}{blob_key} = $blob_key; # for includes
		$link_row{$link_key}{c_a_name} = $c_a_name; # for attachments
		$link_row{$link_key}{c_t_name_key} = $c_t_name; # for topics
		$link_row{$link_key}{c_w_key} = $c_w_key; # for topics
		$link_row{$link_key}{w_key} = $w_key;  # for topic_history
		push(@blobkey_list,$blob_key) if $blob_key;
		push(@blobkey_list,$c_t_name) if $c_t_name;
		push(@blobkey_list,$th_name) if $th_name;
		#print "Fetching Link: $link_key\n";
	}
	my $list_count = scalar(@blobkey_list);
	#print "Number of keys: $list_count\n";
	if($list_count > 0) {
		my %blob_return = %{$this->get_blob_value(@blobkey_list)} if $list_count > 0;
		foreach my $lkey (keys(%link_row)){
			# insert blob values
			$link_row{$lkey}{th_name} = $blob_return{ $link_row{$lkey}{th_name_key} } if $link_row{$lkey}{th_name_key};
			$link_row{$lkey}{c_t_name_key} = $blob_return{ $link_row{$lkey}{c_t_name_key} } if $link_row{$lkey}{c_t_name_key};
			$link_row{$lkey}{blob_key} = $blob_return{ $link_row{$lkey}{blob_key} } if $link_row{$lkey}{blob_key};
		}
	}
	return \%link_row;
}

# for getting the latest revision of Topics
sub getLatestRevisionID_Topic {
	my ($this,$web_name,$topic_name) = @_;
	my ($site_key) = ($this->{site_key});
	my $topic_hunter = $this->{hunter}->{topic_hunter}; # 1-web_name, 2-topic_name
	
	### check the cache for a topic key ###
	my $topic_key = $this->fetchTopicKeyByWT($web_name,$topic_name); 
	my $th_key = $this->fetchTHKeyByWTR($web_name,$topic_name); # no rev # in args so that we get latest revision
	my $th_row_ref = $this->fetchTHRowByTHKey($th_key) if $th_key;
	return $th_row_ref->{revision} if $th_row_ref->{revision}; # returns the 'revision' field for the '-1' topic history row

	### if $th_row_ref->{revision} does not exist, a select query must be done 　###
	$topic_hunter = "'".$topic_key."'" if $topic_key;

	# 2 options, a: COUNT(key) to get max rev, or b: MAX(revision). I am not 20,000 percent sure that revision will be accurate, 
	# so I went with COUNT(key), which will always give the max_rev number
	my $Topic_History = $this->{database_tables}->{Topic_History};
	my $selectStatement_count = qq/SELECT COUNT(th1."key")
		FROM $Topic_History th1 
		WHERE th1.topic_key = ($topic_hunter);/;
	my $selectHandler_count = $this->database_connection()->prepare($selectStatement_count);
	my $bytea_topic_name = sha1($topic_name);
	
	if($topic_key){
		# topic key in cache
		$selectHandler_count->execute;
	}
	else{
		# no topic key in cache
		$selectHandler_count->bind_param( 1, $web_name);

		$selectHandler_count->bind_param( 2, $bytea_topic_name,{ pg_type => DBD::Pg::PG_BYTEA });
		$selectHandler_count->execute;
	}
	my $max_count;
	$selectHandler_count->bind_col( 1, \$max_count );
	while ($selectHandler_count->fetch) {
		return $max_count;
	}
	# nothing really to be put into the cache.  return the max count as the latest revision number
	# TODO: change the query to return some more info, like the th_key
	return $max_count;
}

# load a list of all Topics in a specified web
sub eachTopic {
	my ($this,$web_name) = @_;
	my $site_key = $this->{site_key};
	# don't bother checking the cache for all of the topics
	# get the web key via web hunter
	my $web_hunter = $this->{hunter}->{web_hunter}; # 1-web_name
	my $Topics = $this->getTableName('Topics');
	my $TH = $this->getTableName('Topic_History');
	my $Webs = $this->getTableName('Webs');
	my $BS = $this->getTableName('Blob_Store');
	my $selectStatement_topics = qq/SELECT webs.current_web_name AS web_name, bname."value" AS topic_name, 
  											 th."key" AS th_row_key, t1."key" AS topic_key
FROM 
$TH th
	INNER JOIN $Topics t1 ON t1.link_to_latest = th."key"
	INNER JOIN $BS bname ON bname."key" = th.topic_name
	INNER JOIN $Webs webs ON webs."key" = th.web_key
WHERE 
webs.current_web_name = ? AND
webs.site_key = '$site_key'
ORDER BY topic_name;/;
	my $selectHandler_topics = $this->database_connection()->prepare($selectStatement_topics);
	$selectHandler_topics->bind_param( 1, $web_name);
	$selectHandler_topics->execute;	

	
	my ($return_hash,$topic_key,$topic_name,$link_to_latest, $cweb_name);
	$selectHandler_topics->bind_col( 1, \$cweb_name );
	$selectHandler_topics->bind_col( 2, \$topic_name );
	$selectHandler_topics->bind_col( 3, \$link_to_latest);
	$selectHandler_topics->bind_col( 4, \$topic_key );
	my @arrayWT;
	while ($selectHandler_topics->fetch) {
		push(@arrayWT,$cweb_name.'.'.$topic_name);
	}
	return \@arrayWT;
}

# only inserts the topic key, other fields automatically default to zero in the database.
sub insertTopicRow {
	my ($this,$topic_row_ref) = @_;
	# Name all of the database tables

	my $Topics = $this->getTableName('Topics');
	my $insertStatement = qq/INSERT INTO $Topics ("key", link_to_latest,current_web_key,current_topic_name) VALUES (?,?,?,?) ;/; 
	my $insertHandler = $this->database_connection()->prepare($insertStatement);

	$insertHandler->bind_param( 1, $topic_row_ref->{key} );
	$insertHandler->bind_param( 2, $topic_row_ref->{link_to_latest} );
	$insertHandler->bind_param( 3, $topic_row_ref->{current_web_key} );
	$insertHandler->bind_param( 4, $topic_row_ref->{current_topic_name},{ pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->execute;
	return $topic_row_ref->{key};

}

sub insertTHRow {
	my ($this,$th_row_ref) = @_;
	# Name all of the database tables
	my $Webs = $this->getTableName('Webs');
	my $Topic_History = $this->getTableName('Topic_History');
	my $Topics = $this->getTableName('Topics');

	my $insertStatement = qq/INSERT INTO $Topic_History ("key", topic_key, user_key, web_key, timestamp_epoch, topic_name, topic_content, revision)
VALUES (?,?,?,?,?,?,?,?) ;/; #8 spots, but last spot is the topic_key, a duplicate

	my $th_row_key = $this->_createTHkey($th_row_ref);
	$th_row_ref->{key} = $th_row_key;
	my $insertHandler = $this->database_connection()->prepare($insertStatement);

	$insertHandler->bind_param( 1, $th_row_key ); 
	$insertHandler->bind_param( 2, $th_row_ref->{topic_key}); 
	$insertHandler->bind_param( 3, $th_row_ref->{user_key});
	$insertHandler->bind_param( 4, $th_row_ref->{web_key});
	$insertHandler->bind_param( 5, $th_row_ref->{timestamp_epoch});
	$insertHandler->bind_param( 6, $th_row_ref->{topic_name_key},{ pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->bind_param( 7, $th_row_ref->{topic_content_key},{ pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->bind_param( 8, $th_row_ref->{revision});  # this is to calculate the version number

	$insertHandler->execute;

	return $th_row_key;

}

sub _createTHkey {
	my ($this,$th_row_ref) = @_;
	my $th_key = substr(sha1_hex( $th_row_ref->{topic_key}, $th_row_ref->{user_key}, $th_row_ref->{web_key}, $th_row_ref->{timestamp_epoch}, $th_row_ref->{topic_name_key}, $th_row_ref->{topic_content_key}), 0, - 8);

	return $th_key;
}

sub insertMetaPreference {
	my ($this,$meta_hash) = @_;	

	# key = sha1(1-topic_history_key, 2-name, 3-value) 
	$meta_hash->{'key'} = sha1($meta_hash->{'topic_history_key'}, $meta_hash->{'name'}, $meta_hash->{'value'});

	my $insertStatement = qq/INSERT INTO "MetaPreferences_History" ("key", topic_history_key, "type", "name", "value") VALUES (?,?,?,?,?);/;

	my $insertHandler =  $this->database_connection()->prepare($insertStatement);
	$insertHandler->{RaiseError} = 1;
	$insertHandler->execute($meta_hash->{'key'},$meta_hash->{'topic_history_key'},$meta_hash->{'type'},$meta_hash->{'name'},$meta_hash->{'value'});

}

sub _insertUserTopic {
	my ($this,$web_name,$topic_name,$cUID) = @_;

	my %th_row_ref;
	$th_row_ref{topic_key} = $this->createUUID();
	$th_row_ref{user_key} = $cUID;
	$th_row_ref{web_key} = $this->{web_cache}->{$web_name};
	$th_row_ref{web_name} = $web_name;
	$th_row_ref{timestamp_epoch} = time();
	$th_row_ref{topic_content} = qq^---+!! User: \%TOPIC\% \nDoing fun stuff forever!^;
	$th_row_ref{topic_name} = $topic_name;
	$th_row_ref{revision} = 1;
	
	$th_row_ref{topic_name_key} = $this->insert_Blob_Store($th_row_ref{topic_name});
	$th_row_ref{topic_content_key} = $this->insert_Blob_Store($th_row_ref{topic_content});
	my $th_row_key = $this->insertTHRow(\%th_row_ref);

	# create the topic row
	my %topicrow;
	$topicrow{key}= $th_row_ref{topic_key};
	$topicrow{link_to_latest}= $th_row_key;
	$topicrow{current_web_key}= $th_row_ref{web_key};
	$topicrow{current_topic_name}= $th_row_ref{topic_name_key};
	
	my $topic_key = $this->insertTopicRow(\%topicrow);
	return $topic_key;
}

# do word search
=pod
---+ WordSearch
This function is friggin ugly.  It is direclty connected to Foswiki::Contrib::DBIStoreContrib::ResultSet->new
Becareful when modifying this.
=cut
sub WordSearch {
	my ($this, $query, $inputTopicSet, $session, $options ) = @_;
	my ($site_key) = ($this->{site_key});
	my $webNames = $options->{web}  || $session->{webName};
	$webNames = '' if $webNames eq 'all';
	my $recurse  = $options->{'recurse'} || '';
	my $isAdmin  = $session->{users}->isAdmin( $session->{user} );
	# ordering options
	# $options->{groupby}, $options->{order}, Foswiki::isTrue( $options->{reverse})
	
	my @webNameArray = split(',',$webNames);
	my @webKeyArray;
	my @webQuestionArray;
	foreach my $tempWeb01 (@webNameArray) {
		$tempWeb01 = $this->trim($tempWeb01);
		push(@webKeyArray,$this->{web_cache}->{$tempWeb01});
		push(@webQuestionArray,'?');
	}
	my $WebQuestions = join(',',@webQuestionArray);

	# no inverted keyword searches (ie !Drugs)
    my @listOfTokens = @{ $query->tokens() };
    my $numberOfTokens = scalar(@listOfTokens);
    # make the Token function
    my @questionMarks;
    foreach my $token (@listOfTokens){
    	push(@questionMarks,'?');    	
    }
    my $questionMarksString = join(',',@questionMarks);
    # build the select statement
    my $BS = $this->getTableName('Blob_Store');
    my $Webs = $this->getTableName('Webs');
    my $Topics = $this->getTableName('Topics');
    my $Topic_History = $this->getTableName('Topic_History');
    my $MP = $this->getTableName('Meta_Preferences');

	my $weblimiter = " ";
	if(scalar(@webKeyArray) > 0){
		my $tempWebs = "'".join("','",@webKeyArray)."'";
		$weblimiter = ' AND webs1."key" IN ('.$tempWebs.') ';
	}
	
	my $selectStatement = qq/SELECT th1."key", th1.topic_key, th1.revision, th1.timestamp_epoch, th1.web_key, 
		bsname."value" as topic_name, bscontent.summary as summary, webs1.current_web_name as web_name, th1.user_key,
			mp."name" ||':'|| mp."value" as permissions
FROM foswiki."Topic_History" th1 
	INNER JOIN $BS bsname ON bsname."key" = th1.topic_name
	INNER JOIN $BS bscontent ON bscontent."key" = th1.topic_content
	INNER JOIN $Webs webs1 ON webs1."key" = th1.web_key
	INNER JOIN $Topics topics ON topics.link_to_latest = th1."key"
	LEFT OUTER JOIN $MP mp ON mp.topic_history_key = th1."key" AND mp."type" = 'Set' AND (mp."name" = 'ALLOWTOPICVIEW' OR mp."name" = 'DENYTOPICVIEW')
	WHERE bscontent.value_vector @@ plainto_tsquery('foswiki.all_languages',  ?) AND webs1.site_key = '$site_key' $weblimiter
	ORDER BY web_name ASC, topic_name ASC, timestamp_epoch ASC;/; #1-tokens spaced out
	
    my $selectHandler = $this->database_connection()->prepare_cached($selectStatement);

	# don't execute here!
	# execute the selectHandler
=pod
	my $i = 1;
	foreach my $token02 (@listOfTokens){
    	$selectHandler->bind_param( $i, $token02 );

    	$i = $i + 1;   	
    }
=cut
	$selectHandler->bind_param( 1, join(' ', @listOfTokens ));
	$selectHandler->execute();
	my $arrayReturn_ref = $selectHandler->fetchall_arrayref;
	#  "key", topic_key, revision, timestamp_epoch, web_key, topic_name, summary
	return Foswiki::Contrib::DBIStoreContrib::ResultSet->new($arrayReturn_ref );
}

sub saveToTar {
	my $this = shift;

	# fetch User key + topic_key; Group key + topic_key
	my $UGHash = $this->fetchusergroup();

	require MIME::Base64;

	# load each topic history row, and save it as a tar.gz file
	my $tarHash;	
	# load table names
	my $Webs = $this->getTableName('Webs');
	my $Topics = $this->getTableName('Topics');
	my $Topic_History = $this->getTableName('Topic_History');
	my $MPH = $this->getTableName('Meta_Preferences');
	my $Links = $this->getTableName('Links');
	my $def_field = $this->getTableName('Definition_Field');
	my $data_field = $this->getTableName('Data_Field');
	my $bs = $this->getTableName('Blob_Store');
	my $users = $this->getTableName('Users');
	my $groups = $this->getTableName('Groups');
	my $GroupHistory = $this->getTableName('Group_User_Membership');
	my $siteKey = $this->{site_key};
	# Accounting Plugin
	my $splits = qq/accounts."Splits"/;
	my $transactions = qq/accounts."Transactions"/;

	# Freeswitch Plugin
	my $edittable = qq/foswiki."EditTable_Data"/;

	# set up the topic_history fetch
	# Forbidden characters for delimiters: =,


	my $thstatement = qq/
SELECT 
  th.fake_topic_history_key,   th.topic_key,  th.user_key, 
  th.revision,   th.web_key,  th.timestamp_epoch, 
  th.topic_content,   th.topic_name,
  array_to_string(array_agg(coalesce(mph."type",'')||';'||coalesce(mph."name",'')||';'||coalesce(mph."value",'')),'
') as mphname,
  array_to_string(array_agg(coalesce(l1."link_type",'')||';'||coalesce(l1."destination_topic"::text,'')||';'||
	coalesce(l1."destination_topic_history"::text,'')||';'||coalesce(encode( l1."blob_key", 'base64'),'') ),'
') as linkname,
  array_to_string(array_agg(coalesce(def1.field_key::text,'')||';'||coalesce(encode( def1.field_name, 'base64'),'')||';'||
	coalesce(def1.field_type,'')||';'||coalesce(encode( def1.other_info, 'base64'),'') ),'
') as deffield,
  array_to_string(array_agg(coalesce(data1.field_key::text,'')||';'||coalesce(data1.definition_field_key::text,'')||';'||
	coalesce(encode( data1.field_value, 'base64'),'') ),'
') as datafield,
  array_to_string(array_agg(tname."value"),'') as tcn,
  array_to_string(array_agg(tname.value_vector),'') as tcnvector,
  array_to_string(array_agg(tcontent."value"),'') as tcv,
  array_to_string(array_agg(tcontent.value_vector),'') as tcvvector,
  array_to_string(array_agg(u1."key"||';'||u1.user_topic_key),'') as userkey,
  array_to_string(array_agg(g1."key"||';'||g1.group_topic_key),'') as groupkey,

  array_to_string(array_agg(coalesce(sp1.transaction_key::text,'')||';'||coalesce(sp1.accounts_key::text,'')||';'||coalesce(sp1.amount::text,'') ),'
') as splits,

  array_to_string(array_agg(gh1.user_key::text),'
') as group_member_history,

  array_to_string(array_agg(tx01.post_date ),'
') as transactions,

  1 as authorkey

FROM 
  $Topic_History th
	LEFT JOIN $MPH mph ON th."key" = mph.topic_history_key
	LEFT JOIN $Links l1 ON th."key" = l1.topic_history_key
	LEFT JOIN $def_field def1 ON th."key" = def1.topic_history_key
	LEFT JOIN $data_field data1 ON th."key" = data1.topic_history_key
	LEFT JOIN $bs tname ON th.topic_name = tname."key"
	LEFT JOIN $bs tcontent ON th.topic_content = tcontent."key"
	LEFT JOIN $users u1 ON th.topic_key = u1.user_topic_key AND th.revision = 1
	LEFT JOIN $groups g1 ON th.topic_key = g1.group_topic_key AND th.revision = 1

	LEFT JOIN $splits sp1 ON th.topic_key = sp1.transaction_key AND th.revision = 1
	LEFT JOIN $transactions tx01 ON th.topic_key = tx01.key AND th.revision = 1

	LEFT JOIN $GroupHistory gh1 ON th."key" = gh1.topic_history_key



	INNER JOIN $Webs w1 ON th.web_key = w1."key"

WHERE
  w1.site_key = '$siteKey'
GROUP BY th.fake_topic_history_key,   th.topic_key,  th.user_key,
  th.revision,   th.web_key,  th.timestamp_epoch,
  th.topic_content,   th.topic_name
ORDER BY th.topic_key ASC, th.timestamp_epoch ASC
LIMIT 100;
/;
# INNER JOIN $Webs w1 ON th.web_key = w1."key"
#WHERE
#  w1.site_key = '9ed37a7a-4424-4be7-a5b6-9772a3e6a615'

	my $selectHandler = $this->database_connection()->prepare($thstatement);
	$selectHandler->execute();
	# fetch the links from Links

	my ($thkey,$thtopickey,$thuserkey,$threvision,$thwebkey,
		$thtimestamp,$thtopiccontentkey,$thtopicnamekey,$mphname,$linkname,$deffield,$datafield,
		$tcn,$tcv,$tcnvector,$tcvvector,$u1key,$g1key,
		$sp1row,$gh1row,$txrow,$authorkey);
	$selectHandler->bind_col( 1, \$thkey);
	$selectHandler->bind_col( 2, \$thtopickey);
	$selectHandler->bind_col( 3, \$thuserkey);
	$selectHandler->bind_col( 4, \$threvision);
	$selectHandler->bind_col( 5, \$thwebkey);
	$selectHandler->bind_col( 6, \$thtimestamp);
	$selectHandler->bind_col( 7, \$thtopiccontentkey, { pg_type => DBD::Pg::PG_BYTEA });
	$selectHandler->bind_col( 8, \$thtopicnamekey, { pg_type => DBD::Pg::PG_BYTEA });
	$selectHandler->bind_col( 9, \$mphname);
	$selectHandler->bind_col( 10, \$linkname);
	$selectHandler->bind_col( 11, \$deffield);
	$selectHandler->bind_col(12, \$datafield);
	$selectHandler->bind_col(13, \$tcn);
	$selectHandler->bind_col(14, \$tcnvector);
	$selectHandler->bind_col(15, \$tcv);
	$selectHandler->bind_col(16, \$tcvvector);
        $selectHandler->bind_col(17, \$u1key);
        $selectHandler->bind_col(18, \$g1key);

	$selectHandler->bind_col(19,\$sp1row);

	$selectHandler->bind_col(20,\$gh1row);
	$selectHandler->bind_col(21,\$txrow);
	$selectHandler->bind_col(22,\$authorkey);

	my @blobkeyList;
	my %throwarray;
	require Foswiki::Contrib::DBIStoreContrib::FileBlob;
	while ($selectHandler->fetch) {
		# handle the topic key situation
		my $throwtext = qq/$thtopickey/;
		if($u1key||$g1key){
			$throwtext = qq/$u1key/ if $u1key;
			$throwtext = qq/$g1key/ if $g1key;
		}
		my $delimiter = ";";
		$throwtext .= qq/$delimiter$thuserkey/;
		$throwtext .= qq/$delimiter$threvision/;
		$throwtext .= qq/$delimiter$thwebkey/;
		$throwtext .= qq/$delimiter$thtimestamp/;
		$throwtext .= qq/$delimiter/.MIME::Base64::encode_base64($thtopiccontentkey);
		$throwtext .= qq/$delimiter/.MIME::Base64::encode_base64($thtopicnamekey);
		$tarHash->{$thkey}->{'TH.txt'} = $throwtext;
		$tarHash->{$thkey}->{'MPH.txt'} = $mphname;
		$tarHash->{$thkey}->{'Links.txt'} = $linkname;
		$tarHash->{$thkey}->{'DataForms.txt'} = $deffield;
		$tarHash->{$thkey}->{'DefinitionForms.txt'} = $datafield;
		$tarHash->{$thkey}->{'topic.name'} = $tcnvector;
		$tarHash->{$thkey}->{'topic.content'} = $tcvvector;

		$tarHash->{$thkey}->{'accounting'} = $sp1row;

		$thtopiccontentkey = MIME::Base64::encode_base64($thtopiccontentkey);
		$thtopicnamekey = MIME::Base64::encode_base64($thtopicnamekey);

		$thtopiccontentkey =~ s/\n//g;
		$thtopicnamekey =~ s/\n//g;


		# get working directory
		my $wkdir = $Foswiki::cfg{WorkingDir}.'/fileblob';
		# make the directory in case it does not exist
		`mkdir -p $wkdir` unless -d $wkdir;

		my $thtopickeyFP = $wkdir.'/'.$this->_deriveDirectory($thtopickey);
		my $thkeyFP = $thtopickeyFP.'/'.$this->_deriveDirectory($thkey);

		# strip hyphens
		$thtopickeyFP =~ s/-//g;
		$thkeyFP =~ s/-//g;

		# create topic key folder
		`mkdir -p $thtopickeyFP` unless -d $thtopickeyFP;

		# delete everything in the topic revision (history) folder
		`rm -r $thkeyFP` if -d $thkeyFP;

		# recreate directory
		`mkdir -p $thkeyFP`;






		# define topic history hash
		my $throw = {};
		
		{
			# SINGLE
			# topic history row
			# topic_key, user_key, web_key, timestamp_epoch, topic_content, topic_name, group_key, permissions
			my @x;
			#$thtopickey =~ s/-//g;
			push(@x,$thtopickey); # 'topic_key with no hyphens'
			#$u1key =~ s/-//g;
			push(@x,$u1key); # 'user_key with no hyphens', later put session_id
			#$thwebkey =~ s/-//g;
			push(@x,$thwebkey); # web_key
			push(@x,$thtimestamp); # timestamp_epoch

			$thtopiccontentkey = $this->fetchBlobby($throw,MIME::Base64::decode_base64($thtopiccontentkey),$thkeyFP,$thtopickey);
			push(@x,$thtopiccontentkey); # topic_content

			$thtopicnamekey = $this->fetchBlobby($throw,MIME::Base64::decode_base64($thtopicnamekey),$thkeyFP,$thtopickey);
			push(@x,$thtopicnamekey); # topic_name

			push(@x,''); # group_key (which group owns this page)
			push(@x,2**3); # integer between 0 and 2^9?-1
		
			$throw->{'Topic_History'} = \@x;
			# load Blob keys


		}
		{
			# MULTIPLE
			# Links, sort in alphabetacal order in order of columns
			my %y;
			# l1."link_type"||';'||l1."destination_topic"||';'||l1."destination_topic_history"||';'||l1."blob_key"
			my @links01 = split("\n",$linkname);
			foreach my $singlelink (@links01){
				my @singleLinks02 = split(';',$singlelink);
				# redefine topic_history using new fake thkey
				if(defined $singleLinks02[2]){
					$singleLinks02[2] = $this->fetchFakeTH($singleLinks02[2]);
				}

				if(defined $singleLinks02[3] && $singleLinks02[3] ne ''){
					$singleLinks02[3] = $this->fetchBlobby($throw,MIME::Base64::decode_base64($singleLinks02[3]),$thkeyFP,$thtopickey);
				}
				my @x = ($singleLinks02[0],$singleLinks02[1],$singleLinks02[2],$singleLinks02[3]);
				$y{join('',@x)} = \@x;
			}
		
			my @z;
			foreach my $row (sort keys %y){
				push(@z,$y{$row});
			}
			$throw->{'Links'} = \@z;
			

		}
		{
			# MULTIPLE
			# MPH, sort in alphabetacal order in order of columns
			#  array_to_string(array_agg(coalesce(mph."type",'')||';'||coalesce(mph."name",'')||';'||coalesce(mph."value",'')),'\n') as mphname,
			# $mphname
			my %y;
			foreach my $singlerow (split("\n",$mphname)){
				my @mphrow = split(';',$singlerow);
				my $type = $mphrow[0];
				if(defined $mphrow[1] && defined $mphrow[2]){
					$type = 'local' unless defined $type;
				}

				# change user_key->user_topic_key; group_key->group_topic_key
				my @tmpmphrow;
				foreach my $element (split(',',$mphrow[2])){
					$element =~ s/\s//g;
					push(@tmpmphrow,$UGHash->{$element}) if defined $UGHash->{$element};
					push(@tmpmphrow,$element) unless defined $UGHash->{$element};

					# redefine topic_history using new fake thkey
					if($element =~ m/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/){
						my $xx333 = $1;
						my $possibleTHKey = $this->fetchFakeTH($xx333);
						push(@tmpmphrow,$possibleTHKey) if defined $possibleTHKey;
						
					}
				}
				if(scalar(@tmpmphrow) > 0){
					$mphrow[2] = join(',',@tmpmphrow);
				}

				my @x = ($type,$mphrow[1],$mphrow[2]);
				$y{join('',@x)} = \@x;
			}

			my @z;
			foreach my $row (sort keys %y){
				push(@z,$y{$row});
			}
			$throw->{'MetaPreference_History'} = \@z;
		}

		{
			# MULTIPLE
			# Group_History  , this keeps a history of users who are members
			my %y;
			foreach my $singlerow (split("\n",$gh1row)){
				my @x = ($UGHash->{$singlerow}); # <--- change user_key to user_topic_key
				$y{join('',@x)} = \@x;
			}

			my @z;
			foreach my $row (sort keys %y){
				push(@z,$y{$row});
			}
			$throw->{'Group_User_Membership'} = \@z;
		}
		{
			# SINGLE
			# User_History, sort in alphabetacal order in order of columns
			# this section must be faked, unfortunately
			my $uhtable = qq{"19596cf1-80ad-4503-84cc-fb740ee71e4a";"e8fe9788-2e9a-a626-2cee-da89bff78f66";"";"";"ProjectContributor";"\$2a\$06\$HeSHcgRso9YuDZsF5AjNAuUu8DLJxJu4qSPsEZcneMgOndrXP3RFK";"","375d5c0b-7b1f-4e23-a98a-fc7e48ebe2f1";"124029a7-fe1b-ff47-7a3d-350eb8f72544";"";"";"RegistrationAgent";"\$2a\$06\$WI4ls47ZjQ9MG7pOFWVrauJFoNEmTXTOcBsC12djhJLo4q0GJ2BmS";"","d6a6564c-c1b3-470a-ae47-68dc166b215f";"dfefa69e-5701-bab6-f031-2d405345428c";"";"";"BaseUserMapping_999";"\$2a\$06\$O.HIb9alHczp6tzao7064O1x4XFUbEP8IiXM7HwUty7vw2t.b6iEm";"","3c4d1caa-b4d8-4caa-8a9a-ed7786c2b6de";"72144dcc-a6a5-9213-057c-3b9b95835482";"";"";"guest";"\$2a\$06\$qHCgMk/Zizwrdow6VMIT0.TbsH6d82V9xBqPTjB2WZc9QLDDojxLa";"","471927a1-cbfc-47ac-a4f8-0a90772518c6";"8c913db5-9001-b13b-a0d0-f8e8bc303740";"";"";"admin";"f4dc3f86c8c65d3cd4b045b74545e1d2";"dejesus.joel\@gmail.com","0fd270a3-d72e-4d33-bfca-e6dde2a927de";"9706c56f-1be5-0569-6413-5887333e1112";"";"";"tip32";"b88ab2bfd8e126981f5a3a0db1473a8eaab2c24b";"tip32\@hotmail.com","c158a877-a55f-4d59-92da-0d3bab4b3f07";"7bf2f606-a158-2766-da0e-8d7a5e38c930";"";"";"phone-tokyo001";"goldbaren522";"dejesus.joel\@gmail.com","a7ac9077-3aac-4085-90f7-7b7ab8093291";"f55996ac-343e-3b23-d012-fefc8c1cc227";"";"";"Clearvision";"norikana";"octovision88\@jcom.home.ne.jp","201d0bd2-4ccc-47f7-bda6-a11179ed12aa";"c374f5d5-09a0-1920-c82c-2db4c5aef086";"";"";"rojas.david";"0148a7aaea07189772db115f50b60fc4";"pichonz\@gmail.com","1a3d565c-0fee-4129-8f50-49b43703cd1f";"fbc189ee-c313-c84b-7494-fc1af12033b3";"Joel";"DeJesus";"dejesus.joel";"669cdad209507322a1ddfe10f49b05da";"dejesus.joel\@e-flamingo.jp","645b22a8-f772-11e1-908e-423a3e45401f";"eb957292-d7c2-ac66-007b-a7fdbe213d72";"";"";"stewart.dallas";"e83c9b4926141d34997a36d5c399f24b";"stewartdallas\@veryfast.biz","e27219e8-8f4a-11e1-b653-8a6a3baf19b4";"71bc9f5a-3711-bf04-472c-7f5ca14df654";"";"";"julissa.dejesus";"032749caab9ef825ec8206467d7d8adf";"julissa.dejesus21\@gmail.com","63a14d08-2178-11e2-b507-63103e45401f";"e8f5863b-03c6-8437-d53d-78af9d38f861";"";"";"nakao.yohei";"96385e46475114228b0b2b521f1df074";"ynakao\@cgikk.com","d62b5e1d-dcfc-48e0-9006-1364ea32c89a";"e503772a-58f1-4840-a9ff-d8663457a226";"";"";"ninjaman";"042832ac73d5bf18e22bec9c955248d6";"dejesus.joel\@gmail.com","80c05e5f-71a5-421d-8329-9f8e6e7633b7";"4b5e145c-422a-97e5-3357-80185671eb9b";"";"";"takai.ayumi";"b0bca155de64fba2ee10625d8d64a28e";"takai.ayumi\@gmail.com","33cd6a12-c28e-46ca-9f43-1b727bfb816a";"fb3e4983-492a-d6d6-804c-633bf9723a9d";"";"";"share.elmo";"98036a06671e9c987c451502e50d0be2";"share.elmo\@gmail.com","fa0439a6-81ac-11e2-b2c2-af766226fef1";"bce99b61-78a8-c1ae-9869-45272705b478";"";"";"tina.rehe";"2d11d9e9c69fdd9d3c00fcead7f6c127";"tina.rehe\@gmail.com"};
			$uhtable =~ s/"//g;
			my @uht1 = split(',',$uhtable);

			my $userhistoryhash = {};
			foreach my $uhtt0 (@uht1){
				my @uht2 = split(';',$uhtt0);
				my @uht3;
				foreach my $uhtt22 (@uht2){
					push(@uht3,$uhtt22);
				}
				$userhistoryhash->{$uht3[0]} = \@uht3;
				# remove hyphens
				
#die "($thtopickey)(".$uht3[0].")";
				next unless $thtopickey eq $uht3[0];			
				#   u1.user_topic_key,  uh.key, uh.first_name, uh.last_name, uh.login_name, uh.password, uh.email, uh.country, uh.callback_number, uh.gpg_key
				my @x;
				push(@x,$uht3[2]); # <-- first_name 
				push(@x,$uht3[3]); # <-- last_name
				push(@x,$uht3[5]); # <-- password connected to Blob_Store?
				push(@x,$uht3[0]); # <--- points to a topic_key
				push(@x,$uht3[6]); # <--- email
				push(@x,$uht3[7]); # <--- country
				push(@x,$uht3[8]); # <--- callback_number
				push(@x,$uht3[9]); # <---gpg key (search and replace s/\n/NEWLINE/g)
				$throw->{'User_History'} = \@x;
			}

		}
		{
			# MUTLIPLE
			# Dataform_Data_Field, sort in alphabetacal order in order of columns
			my @x;
			my %y;
			#    array_to_string(array_agg(coalesce(data1.field_key::text,'')||';'||coalesce(data1.definition_field_key::text,'')||';'||
			#	coalesce(encode( data1.field_value, 'base64'),'') ),'

			
			foreach my $singlerow (split("\n",$datafield)){
				my @srow = split(";",$singlerow);
				my @x;
				push(@x,$srow[1]); # <--- definition_field_key 
				$srow[2] = $this->fetchBlobby($throw,MIME::Base64::decode_base64($srow[2]),$thkeyFP,$thtopickey) if defined $srow[2] && $srow[2] ne '';
				push(@x,$srow[2]); # <--- field_value
				$y{join('',@x)} = \@x;
			}

			my @z;
			foreach my $row (sort keys %y){
				push(@z,$y{$row});
			}
			$throw->{'Dataform_Data_Field'} = \@z;
		}
		{
			# MUTLIPLE
			# Dataform_Definition_Field, sort in alphabetacal order in order of columns
			my @x;
			my %y;
			#  array_to_string(array_agg(coalesce(def1.field_key::text,'')||';'||coalesce(encode( def1.field_name, 'base64'),'')||';'||
			#	coalesce(def1.field_type,'')||';'||coalesce(encode( def1.other_info, 'base64'),'') ),'

			foreach my $singlerow (split("\n",$deffield)){
				my @srow = split(";",$singlerow);
				my @x;
				$srow[1] = $this->fetchBlobby($throw,MIME::Base64::decode_base64($srow[1]),$thkeyFP,$thtopickey)  if defined $srow[1] && $srow[1] ne '';
				push(@x,$srow[1]); # <--- field_name base64
				push(@x,$srow[2]); # <--- field_type (just text)
				$srow[3] = $this->fetchBlobby($throw,MIME::Base64::decode_base64($srow[3]),$thkeyFP,$thtopickey)  if defined $srow[3] && $srow[3] ne '';
				push(@x,$srow[3]); # <--- other_info base64
				$y{join('',@x)} = \@x;
			}

			my @z;
			foreach my $row (sort keys %y){
				push(@z,$y{$row});
			}
			$throw->{'Dataform_Definition_Field'} = \@z;
		}
		{
			# Topic, MULTIPLE
			# Splits, sort in alphabetacal order in order of columns
			# ...stored with transaction topic, allowing with Transactions row
			my @x;
			my %y;
			#    array_to_string(array_agg(coalesce(sp1.transaction_key::text,'')||';'||coalesce(sp1.accounts_key::text,'')||';'||coalesce(sp1.amount::text,'') ),'\n')

			foreach my $singlerow (split("\n",$sp1row)){
				my @srow = split(";",$singlerow);
				my @x;
				push(@x,$srow[1]); # <--- account_key
				push(@x,$srow[2]); # <--- amount
				$y{join('',@x)} = \@x;
			}
			my @z;
			foreach my $row (sort keys %y){
				push(@z,$y{$row});
			}
			$throw->{'Splits'} = \@z;

			# Topic, SINGLE
			# tx01.post_data $txrow
			$txrow = s/\n//g;
			my @a = ($txrow);
			$throw->{'Transactions'} = \@a;
		}
		{
			# Topic, SINGLE
			# Users
			#   array_to_string(array_agg(u1."key"||';'||u1.user_topic_key),'') as userkey,
			my $uhtable = qq{"19596cf1-80ad-4503-84cc-fb740ee71e4a";"e8fe9788-2e9a-a626-2cee-da89bff78f66";"";"";"ProjectContributor";"\$2a\$06\$HeSHcgRso9YuDZsF5AjNAuUu8DLJxJu4qSPsEZcneMgOndrXP3RFK";"","375d5c0b-7b1f-4e23-a98a-fc7e48ebe2f1";"124029a7-fe1b-ff47-7a3d-350eb8f72544";"";"";"RegistrationAgent";"\$2a\$06\$WI4ls47ZjQ9MG7pOFWVrauJFoNEmTXTOcBsC12djhJLo4q0GJ2BmS";"","d6a6564c-c1b3-470a-ae47-68dc166b215f";"dfefa69e-5701-bab6-f031-2d405345428c";"";"";"BaseUserMapping_999";"\$2a\$06\$O.HIb9alHczp6tzao7064O1x4XFUbEP8IiXM7HwUty7vw2t.b6iEm";"","3c4d1caa-b4d8-4caa-8a9a-ed7786c2b6de";"72144dcc-a6a5-9213-057c-3b9b95835482";"";"";"guest";"\$2a\$06\$qHCgMk/Zizwrdow6VMIT0.TbsH6d82V9xBqPTjB2WZc9QLDDojxLa";"","471927a1-cbfc-47ac-a4f8-0a90772518c6";"8c913db5-9001-b13b-a0d0-f8e8bc303740";"";"";"admin";"f4dc3f86c8c65d3cd4b045b74545e1d2";"dejesus.joel\@gmail.com","0fd270a3-d72e-4d33-bfca-e6dde2a927de";"9706c56f-1be5-0569-6413-5887333e1112";"";"";"tip32";"b88ab2bfd8e126981f5a3a0db1473a8eaab2c24b";"tip32\@hotmail.com","c158a877-a55f-4d59-92da-0d3bab4b3f07";"7bf2f606-a158-2766-da0e-8d7a5e38c930";"";"";"phone-tokyo001";"goldbaren522";"dejesus.joel\@gmail.com","a7ac9077-3aac-4085-90f7-7b7ab8093291";"f55996ac-343e-3b23-d012-fefc8c1cc227";"";"";"Clearvision";"norikana";"octovision88\@jcom.home.ne.jp","201d0bd2-4ccc-47f7-bda6-a11179ed12aa";"c374f5d5-09a0-1920-c82c-2db4c5aef086";"";"";"rojas.david";"0148a7aaea07189772db115f50b60fc4";"pichonz\@gmail.com","1a3d565c-0fee-4129-8f50-49b43703cd1f";"fbc189ee-c313-c84b-7494-fc1af12033b3";"Joel";"DeJesus";"dejesus.joel";"669cdad209507322a1ddfe10f49b05da";"dejesus.joel\@e-flamingo.jp","645b22a8-f772-11e1-908e-423a3e45401f";"eb957292-d7c2-ac66-007b-a7fdbe213d72";"";"";"stewart.dallas";"e83c9b4926141d34997a36d5c399f24b";"stewartdallas\@veryfast.biz","e27219e8-8f4a-11e1-b653-8a6a3baf19b4";"71bc9f5a-3711-bf04-472c-7f5ca14df654";"";"";"julissa.dejesus";"032749caab9ef825ec8206467d7d8adf";"julissa.dejesus21\@gmail.com","63a14d08-2178-11e2-b507-63103e45401f";"e8f5863b-03c6-8437-d53d-78af9d38f861";"";"";"nakao.yohei";"96385e46475114228b0b2b521f1df074";"ynakao\@cgikk.com","d62b5e1d-dcfc-48e0-9006-1364ea32c89a";"e503772a-58f1-4840-a9ff-d8663457a226";"";"";"ninjaman";"042832ac73d5bf18e22bec9c955248d6";"dejesus.joel\@gmail.com","80c05e5f-71a5-421d-8329-9f8e6e7633b7";"4b5e145c-422a-97e5-3357-80185671eb9b";"";"";"takai.ayumi";"b0bca155de64fba2ee10625d8d64a28e";"takai.ayumi\@gmail.com","33cd6a12-c28e-46ca-9f43-1b727bfb816a";"fb3e4983-492a-d6d6-804c-633bf9723a9d";"";"";"share.elmo";"98036a06671e9c987c451502e50d0be2";"share.elmo\@gmail.com","fa0439a6-81ac-11e2-b2c2-af766226fef1";"bce99b61-78a8-c1ae-9869-45272705b478";"";"";"tina.rehe";"2d11d9e9c69fdd9d3c00fcead7f6c127";"tina.rehe\@gmail.com"};
			$uhtable =~ s/"//g;
			my @uht1 = split(',',$uhtable);

			my $userhistoryhash = {};
			foreach my $uhtt0 (@uht1){
				my @uht2 = split(';',$uhtt0);
				my @uht3;
				foreach my $uhtt22 (@uht2){
					push(@uht3,$uhtt22);
				}
				# remove hyphens
				
#die "($thtopickey)(".$uht3[0].")";
				next unless $thtopickey eq $uht3[0];			
				#   u1.user_topic_key,  uh.key, uh.first_name, uh.last_name, uh.login_name, uh.password, uh.email, uh.country, uh.callback_number, uh.gpg_key
				my @x;
				push(@x,$uht3[4].'__tokyo'); # <-- first_name 
				$throw->{'Users'} = \@x;
			}

		}
		{
			# Topic, SINGLE
			# Groups
			#  array_to_string(array_agg(g1."key"||';'||g1.group_topic_key),'') as groupkey,
			my @x = split(';',$g1key);
			my @z = (1);
			
			$throw->{'Groups'} = \@z if defined $g1key && $g1key ne '';
		}
		$throwarray{$thkey} = $throw;
		# let's go through and put everything in order
		my $output = "";

		

		my $fileblob = Foswiki::Contrib::DBIStoreContrib::FileBlob::->new({'topic_revision_info' => $throw, 'ID' => $this->fetchIBE($thtopickey) });
		#my $fileblob = Foswiki::Contrib::DBIStoreContrib::FileBlob::->new();
		#my $mothershipsig = $fileblob->verifyTOPT(123456,'ca761232-ed42-11ce-bacd-00aa0057b223');
		
		#require Data::Dumper;
		#my $xoo = Data::Dumper::Dumper($mothershipsig);
		#die "Hopeless:\n$xoo";
		$fileblob->encrypt();		
		$fileblob->upload();
		#die "what's up?";
	}



	die "hello, finished!";
	#require Data::Dumper;
	#my $output = Data::Dumper::Dumper(%throwarray);
	#die "$output";
}
# ($topickey)-> relative file path
sub _deriveDirectory {
	my $this = shift;
	my $sha = shift;

	# don't laugh, this is ugly
	my @array = split('',$sha);
	my $nested = "";
	my $counter = 0;
	foreach my $char (@array){
		$nested .= $char;
		$nested .= '/' if $counter == 1; # / after the second character
		$nested .= '/' if $counter == 4; # / after the fifth character
		$counter++;
	}
	
	return $nested;
}

sub fetchusergroup {
	my $this = shift;

	my $statement = qq/SELECT u1."key", u1.user_topic_key FROM foswiki."Users" u1 UNION SELECT g1."key", g1.group_topic_key FROM foswiki."Groups" g1/;

	my $selectHandler = $this->database_connection()->prepare($statement);
	$selectHandler->execute();

	my ($key,$topickey);
	$selectHandler->bind_col( 1, \$key);
	$selectHandler->bind_col( 2, \$topickey);

	my $answer = {};

	while ($selectHandler->fetch) {
		$answer->{$key} = $topickey;
		$answer->{$topickey} = $key;
	}
	return $answer;
}
# fetches blobby value, writes it to disk
# fetchBlobby($throw,$blobkey,$directory,$topickey)
sub fetchBlobby {
	my $this = shift;
	my $throw = shift;
	my $key = shift;
	my $dir = shift;
	my $topickey = shift;
	my @bsarray;
	if(defined $throw->{'Blob_Store'} && ref($throw->{'Blob_Store'}) eq 'ARRAY' ){
		@bsarray = @{$throw->{'Blob_Store'}};
	}
	else{
		@bsarray = ();
	}

	die "no directory!" unless -d $dir;
	`mkdir -p $dir/Blob_Store` unless -d "$dir/Blob_Store";

	my $statement = qq/SELECT "value" FROM foswiki."Blob_Store" WHERE "key" = ? /;

	my $selectHandler = $this->database_connection()->prepare($statement);
	$selectHandler->bind_param(1,$key,{ pg_type => DBD::Pg::PG_BYTEA });
	$selectHandler->execute;
	my ($value);
	$selectHandler->bind_col( 1, \$value);

	while ($selectHandler->fetch) {
		# generate random file name
		my $tmpname = $dir.'/Blob_Store/'.$this->_randomPassword(12);
		open( MYFILE,">", $tmpname) or die "can't create Blob file!";
		print MYFILE "$value";
		close MYFILE;
		
		# generate sha256sum(topic_key,filename)
		my $newfilenameCell = `sha256sum $tmpname` if -f $tmpname;
		if($newfilenameCell =~ m/^([a-z0-9]+)/){
			$newfilenameCell = $1;
		}
		else{
			die "something wrong with sha256sum.";
		}
		$newfilenameCell = sha256_hex($topickey.$newfilenameCell);
		# move the tmp file to it's new location
		my $new002002 = $dir.'/Blob_Store/'.$newfilenameCell;
		`mv $tmpname $new002002`;

		my @x = ($newfilenameCell,$value);		
		push(@bsarray,\@x);
		$throw->{'Blob_Store'} = \@bsarray;
		return $newfilenameCell;
	}
	die "missing Blob Value!";
}

=pod
---++ fetchIBE($topic_key)->\(web_history_key,topic_key) 
We have to fetch the latest site_history_key and web_history_key.  There are no hyphens.
=cut
sub fetchIBE {
	my $this = shift;
	my $topickey = shift;
	die "No topic key" unless defined $topickey;
	my $Topics = $this->getTableName('Topics');
	my $Webs = $this->getTableName('Webs');
	my $Sites = $this->getTableName('Sites');

	my $statement = qq/
SELECT 
  s1.link_to_latest,
  w1.link_to_latest
FROM 
$Webs w1
  INNER JOIN $Topics t1 ON t1.current_web_key = w1."key"
  INNER JOIN $Sites s1 ON s1."key" = w1.site_key
WHERE
  t1."key" = ?
/;

	my $selectHandler = $this->database_connection()->prepare($statement);
	$selectHandler->bind_param(1,$topickey);
	$selectHandler->execute;
	my ($shkey,$whkey);
	$selectHandler->bind_col( 1, \$shkey);
	$selectHandler->bind_col( 2, \$whkey);

	while ($selectHandler->fetch) {
		$shkey =~ s/\-//g;
		$whkey =~ s/\-//g;
		$topickey =~ s/\-//g;
		my @x = ($shkey,$whkey,$topickey);
		return \@x;
	}
	die "missing Web History Value!";
}

=pod
---++ fetchFakeTH($th_key)->$fake_th_key
=cut
sub fetchFakeTH {
	my $this = shift;
	my $thkey = shift;
	die "No th key" unless defined $thkey;
	my $TH = $this->getTableName('Topic_History');

	my $statement = qq/
SELECT 
  fake_topic_history_key
FROM 
$TH
WHERE
  "key" = ?
/;

	my $selectHandler = $this->database_connection()->prepare($statement);
	$selectHandler->bind_param(1,$thkey);
	$selectHandler->execute;
	my ($fakekey);
	$selectHandler->bind_col( 1, \$fakekey);

	while ($selectHandler->fetch) {
		return $fakekey;
	}
	return undef;
}

=pod
---+++ randomPassword($numOfCharacters)->random password
This is used for the symmetric encryption
=cut

sub _randomPassword {
	my $this = shift;
my $password;
my $_rand;

my $password_length = $_[0];
    if (!$password_length) {
        $password_length = 12;
    }
# this array is 26*2 + 10 = 62
my @chars = split(" ",
    "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9");

srand;

for (my $i=0; $i <= $password_length ;$i++) {
    $_rand = int(rand 61);
    $password .= $chars[$_rand];
}
return $password;
}

1;
__END__

