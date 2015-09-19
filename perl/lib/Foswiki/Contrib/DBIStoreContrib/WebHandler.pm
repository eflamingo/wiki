# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::WebHandler;

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
use File::Slurp qw(write_file);
use DBI qw(:sql_types);
use File::Basename				();

use base ("Foswiki::Contrib::DBIStoreContrib::Handler");

############################################################################################
########################            Fetching Functions         #############################
############################################################################################


# same arg as Handler->new();
sub new {
	return shift->SUPER::new(@_);
}

sub init {
	# TODO:check that the argument is a handler object First!
	# blah........
	my $class = shift;
	my $this = shift;
	return bless($this,$class);
}


sub LoadListOfWebs {
	my ($this,$web_name) = @_;
	# one day, there will be subwebs... but not today
	my $site_key = $this->{site_key};
	# get database tables
	my $Webs = $this->getTableName('Webs');
	my $selectStatement = qq/SELECT w1."key", w1.web_home, w1.current_web_name FROM $Webs w1 WHERE w1.site_key = '$site_key';/;
	my $webHandler = $this->database_connection()->prepare($selectStatement);
	$webHandler->execute;
	my ($web_key,$cweb_name,$web_home);
	$webHandler->bind_col(1, \$web_key );
	$webHandler->bind_col(2, \$web_home );
	$webHandler->bind_col(3, \$cweb_name );
	my @list;
	while ($webHandler->fetch) {
		# Only one row should be returned.
		push(@list,$cweb_name);
		# some day, come out with a better iterator
	}
	return \@list;
}

sub fetchWebRowKeyByW {
	my ($this,$web_name) = @_;

	my $web_key = $this->{web_cache}->{$web_name};
	return $web_key;
}

sub insertNewWeb {
	my $this = shift;
	my $websRow = shift;
	my $site_key = $this->{site_key};
	$websRow->{timestamp_epoch} ||= time();

	my $l2l = $this->insertWH({key => '', web_key => $websRow->{key},
				timestamp_epoch => $websRow->{timestamp_epoch},user_key => $websRow->{user_key}, web_name => $websRow->{web_name}});
				
	$this->insertWebs({ key => $websRow->{key}, link_to_latest => $l2l,current_web_name => $websRow->{current_web_name}, 
			site_key => $site_key, web_preferences => $websRow->{web_preferences}, web_home => $websRow->{web_home}});
}

sub insertWebs {
	my $this = shift;
	my $websRow = shift;
	my $Webs = 	$this->getTableName('Webs');
	my $insertStatement = qq/INSERT INTO $Webs ("key",link_to_latest, current_web_name, site_key, web_preferences, web_home) 
		 VALUES (?,?,?,?,?,?);/;
		 	
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->execute($websRow->{key},$websRow->{link_to_latest},$websRow->{current_web_name},
		$websRow->{site_key},$websRow->{web_preferences},$websRow->{web_home});
	return $websRow->{key};

}

sub insertWH {
	my $this = shift;
	my $whRow = shift;
	my $whkey = $this->_generateWHKey($whRow);
	my $WH = $this->getTableName('Web_History');
	my $insertStatement = qq/INSERT INTO $WH ("key", web_key, timestamp_epoch, user_key, web_name) VALUES (?,?,?,?,?); /;
	my ($web_key,$timestamp,$cUID,$web_name) = ($whRow->{web_key},$whRow->{timestamp_epoch},$whRow->{user_key},$whRow->{web_name});
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->execute($whkey,$whRow->{web_key},$whRow->{timestamp_epoch},
		$whRow->{user_key},$whRow->{web_name});
	return $whkey;
}
# key = sha1( 1-web_key, 2-timestamp_epoch, 3-user_key, 4-site_key) 
sub _generateWHKey {
	my $this = shift;
	my $whRow = shift;
	return substr(sha1_hex($whRow->{web_key},$whRow->{timestamp_epoch},$whRow->{user_key},$whRow->{site_key}),0,-8);
}


1;

__END__

	$websRow->{key} = $new_web_key;
	$websRow->{link_to_latest} = '00000000-0000-0000-0000-000000000000';
	$websRow->{current_web_name} = $new_web_name;
	$websRow->{site_key} = $site_key;
	$websRow->{web_preferences} = '';
	$websRow->{web_home} = '';
	$websRow->{timestamp_epoch} = time();
	$websRow->{user_key} = $user_key;
	$websRow->{web_name} = $new;


webs -> web_preferences, web_home
Extra: WebAtom.txt  WebChanges.txt  WebCreateNewTopic.txt  WebHome.txt  WebIndex.txt  

WebNotify.txt  WebPreferences.txt  WebRss.txt  WebSearchAdvanced.txt  WebSearch.txt  WebStatistics.txt  WebTopicList.txt

CREATE TABLE foswiki."Webs"
(
  "key" uuid NOT NULL,
  link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
  current_web_name text DEFAULT 'Name me something nice'::text,
  site_key uuid NOT NULL,
  web_preferences uuid NOT NULL,
  web_home uuid NOT NULL,
)
WITH (
  OIDS=FALSE
);
ALTER TABLE foswiki."Webs" OWNER TO foswikiroot;

CREATE TABLE foswiki."Web_History"
(
  "key" uuid NOT NULL,
  web_key uuid NOT NULL,
  timestamp_epoch integer NOT NULL,
  user_key uuid NOT NULL,
  web_name text NOT NULL,
)
WITH (
  OIDS=FALSE
);
ALTER TABLE foswiki."Web_History" OWNER TO foswikiroot;

