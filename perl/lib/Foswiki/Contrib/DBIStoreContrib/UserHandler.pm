# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::UserHandler;

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
use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Slurp qw(write_file);
use DBI qw(:sql_types);
use File::Basename				();

use base ("Foswiki::Contrib::DBIStoreContrib::Handler");

=pod
$this->{user_cache}->{$user_key} = latest_user_history_row
$this->{user_cache}->{$login_name} = $user_key
$this->{user_cache}->{'topic_key'.$topic_key} = $user_key
$this->{user_cache}->{'groups'.$user_key} = \@group_keys
$this->{user_cache}->{'groups'.$user_key.'scooped'} = 0/1 # so that 
=cut


############################################################################################
########################              Constructors             #############################
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


# (cUID) -> login_name (the current one)
sub getLoginName_User {
	my $this = shift;
	my $user_key = shift;
	# make sure that the input is a GUID
	$user_key = $this->checkUUID($user_key);
	return undef unless $user_key;
	my $Users = $this->{database_tables}->{Users};
	my $selectStatement_user = qq/SELECT $Users.current_login_name FROM $Users WHERE $Users."key" = ? ;/; # 1-user_key

	my $selectHandler_user = $this->database_connection()->prepare($selectStatement_user);
	
	$selectHandler_user->bind_param( 1, $user_key);
	$selectHandler_user->execute;

	my $login_name;
	$selectHandler_user->bind_col( 1, \$login_name );
	while ($selectHandler_user->fetch) {
		# TODO: stuff this into some sort of cache
		return $login_name;
	}

	return undef;
}


# getWikiName_User(cUID) -> { web_name => Main, bytea_topic_name => 'Admin'::bytea} hash return
sub getWikiName_User {
	my $this = shift;
	my $user_key = shift;
	# make sure that the input is a GUID
	$user_key = $this->checkUUID($user_key);
	return undef unless $user_key;

	# get database tables
	my $Users = $this->{database_tables}->{Users};
	my $Topics = $this->{database_tables}->{Topics};
	my $Webs = $this->{database_tables}->{Webs};

	my $selectStatement_user = qq/SELECT $Webs.current_web_name, $Topics.current_topic_name
		FROM $Topics 
		INNER JOIN $Webs ON $Topics.current_web_key = $Webs."key"
		INNER JOIN $Users ON $Topics."key" = $Users.user_topic_key
		WHERE $Users."key" = ? ;/; # 1-user_key

	my $selectHandler_user = $this->database_connection()->prepare($selectStatement_user);
	
	$selectHandler_user->bind_param( 1, $user_key);
	$selectHandler_user->execute;

	my %return_hash;
	my ($web_name,$bytea_topic_name);
	$selectHandler_user->bind_col( 1, \$web_name);
	$selectHandler_user->bind_col( 2, \$bytea_topic_name,{ pg_type => DBD::Pg::PG_BYTEA });
	while ($selectHandler_user->fetch) {
		# TODO: stuff this into some sort of cache
		# returns the wiki_name in binary form, not text!
		$return_hash{web_name} = $web_name;
		$return_hash{bytea_topic_name} = $bytea_topic_name;
		return \%return_hash;
	}

	return undef;
}

# getEmailsWithUserKey(cUID) -> $stringList of emails that are comma delimited
sub getEmailsWithUserKey {
	my $this = shift;
	my $user_key = shift;
	# make sure that the input is a GUID
	$user_key = $this->checkUUID($user_key);
	return undef unless $user_key;

	# get database tables
	my $Users = $this->{database_tables}->{Users};
	my $UH = $this->{database_tables}->{User_History};


	my $selectStatement_user = qq/SELECT uh.email FROM $UH uh INNER JOIN $Users users ON uh."key" = users.link_to_latest
  		WHERE users."key" = ? ;/; # 1-user_key

	my $selectHandler_user = $this->database_connection()->prepare($selectStatement_user);
	
	$selectHandler_user->bind_param( 1, $user_key);
	$selectHandler_user->execute;

	my %return_hash;
	my ($email);
	$selectHandler_user->bind_col( 1, \$email);
	while ($selectHandler_user->fetch) {
		# returns the comma delimited list of emails
		return $email;
	}
	return undef;
}

# () -> @allusers (user_keys)
sub getAllUsers {
	my $this = shift;
	my $site_key = $this->{site_key};

	# get database tables
	my $Users = $this->{database_tables}->{Users};

	my $selectStatement_user = qq/SELECT $Users."key" FROM $Users WHERE $Users.site_key = '$site_key' ;/; # 1-user_key

	my $selectHandler_user = $this->database_connection()->prepare($selectStatement_user);
	$selectHandler_user->execute;

	my @return_array = ();
	my ($user_key);
	$selectHandler_user->bind_col( 1, \$user_key);
	while ($selectHandler_user->fetch) {
		# TODO: stuff this into some sort of cache
		push(@return_array,$user_key);
	}
	return \@return_array;
}
# (login_name) -> passwdE (password ciphertext)
sub fetchPassWithLoginName {
	my ($this,$login_name) = @_;

	my $site_key = $this->{site_key};
	my $Users = $this->{database_tables}->{Users};
	my $UH = $this->{database_tables}->{User_History};

	# DON'T FORGET THE SITE KEY!!!!!!!!!!!!!!!!!!!!!!
	my $Webs = $this->{database_tables}->{Webs};
	my $selectStatement_pw = qq/SELECT $UH."password", $UH.login_name
		FROM $Users INNER JOIN $UH ON $Users.link_to_latest = $UH."key"
		WHERE $Users.site_key = '$site_key' AND $UH.login_name = ? ;/;

	my $selectHandler_pw = $this->database_connection()->prepare($selectStatement_pw);
	$selectHandler_pw->execute($login_name);

	my ($passwdE);
	$selectHandler_pw->bind_col( 1, \$passwdE);
	while ($selectHandler_pw->fetch) {
		# TODO: stuff this into some sort of cache
		#print "Got password! $passwdE\n";
		return $passwdE;
	}
	return undef;

}


# login_name -> cUID
sub fetchcUIDwithLogin {
	my ($this,$login_name) = @_;
	
	my $site_key = $this->{site_key};
	my $Users = $this->{database_tables}->{Users};

	# DON'T FORGET THE SITE KEY!!!!!!!!!!!!!!!!!!!!!!
	my $Webs = $this->{database_tables}->{Webs};
	my $selectStatement_user = qq/SELECT $Users."key"
		FROM $Users
		WHERE $Users.site_key = '$site_key' AND $Users.current_login_name = ? ;/;

	my $selectHandler_user = $this->database_connection()->prepare($selectStatement_user);
	$selectHandler_user->execute($login_name);

	my ($user_key);
	$selectHandler_user->bind_col( 1, \$user_key);
	while ($selectHandler_user->fetch) {
		# TODO: stuff this into some sort of cache
		return $user_key;
	}
	return undef;
}

# wiki_name (web,topic) -> cUID
sub fetchcUIDwithWikiName {
	my ($this,$web_name,$topic_name) = @_;
	my $site_key = $this->{site_key};
	return undef unless $web_name; # kill if no web is specified
	my $bytea_topic_name = sha1($topic_name);	

	my $Users = $this->getTableName('Users');

	# DON'T FORGET THE SITE KEY!!!!!!!!!!!!!!!!!!!!!!
	my $Webs = $this->{database_tables}->{Webs};
	my $topic_hunter = $this->{hunter}->{topic_hunter};
	my $selectStatement_user = qq/SELECT 
  u1."key"
FROM 
  foswiki."Topics" t1
    INNER JOIN foswiki."Users" u1 ON u1.user_topic_key = t1."key"
    INNER JOIN foswiki."Blob_Store" bname ON bname."key" = t1.current_topic_name
    INNER JOIN foswiki."Webs" w1 ON w1."key" = t1.current_web_key
WHERE 
  w1.site_key = '$site_key' AND w1."current_web_name" = ? AND bname."value" = ? ;
;/; # 1-web_name, 2-topic_name


	
	my $selectHandler_user = $this->database_connection()->prepare($selectStatement_user);
	$selectHandler_user->execute($web_name,$topic_name);

	my ($user_key);
	$selectHandler_user->bind_col( 1, \$user_key);
	while ($selectHandler_user->fetch) {
		# TODO: stuff this into some sort of cache
		return $user_key;
	}
	return undef;
}

# wiki_name (\@web,topic, pairs) -> reference to array of keys (cUID or group keys)
sub fetchcUIDOrGroupKeyByWikiName {

	my ($this,@ugpairs) = @_;
	my $site_key = $this->{site_key};

	my $scalar = scalar(@ugpairs);
	return undef if $scalar == 0;
	# create an array of hashes
	my (@arrayOfWT,@arrayOfQ);
	my %wtexists;
	foreach my $webtopic (@ugpairs) {
		$webtopic = $this->trim($webtopic);
		my $WTpairs = {};
		my ($webname1,$topicname1) = Foswiki::Func::normalizeWebTopicName('Main',$webtopic);
		my $mainweb = $this->{web_cache}->{'Main'};
		my $web_key1 = $this->{web_cache}->{$webname1} || $mainweb;
		$WTpairs->{web_key} = $web_key1; 
		$WTpairs->{bytea_topicname} = sha1($topicname1);
		$wtexists{join('',$WTpairs->{web_key},$WTpairs->{bytea_topicname})} = 1;
		push(@arrayOfWT,$WTpairs);
		push(@arrayOfQ,'?');
	}
	# if only 1 element is in the array
	my $stringOfQ = '?';
	$stringOfQ = join(',',@arrayOfQ) if $scalar > 1;
	

	# Setup the tables
	my $Users = $this->getTableName('Users');
	my $Groups = $this->getTableName('Groups');
	my $Topics = $this->getTableName('Topics');
	my $BS = $this->getTableName('Blob_Store');

	my $selectStatement_user = qq/SELECT 
  users."key",
  groups."key",
  topics.current_web_key,
  topics.current_topic_name
FROM 
$Topics topics
LEFT OUTER JOIN $Users users ON users.user_topic_key = topics."key"
LEFT OUTER JOIN $Groups groups ON groups.group_topic_key = topics."key"
WHERE
(users.site_key = '$site_key' OR groups.site_key = '$site_key') AND
topics.current_topic_name IN ($stringOfQ);/; 

	my $selectHandler_user = $this->database_connection()->prepare($selectStatement_user);
	
	# put in the bytea topic names
	my $i = 1;
	foreach my $wtpair2 (@arrayOfWT) {
		$selectHandler_user->bind_param( $i, $wtpair2->{bytea_topicname},{ pg_type => DBD::Pg::PG_BYTEA });
		$i = $i + 1;
	}
	$selectHandler_user->execute;

	my ($user_key,$group_key,$web_key,$btn);
	$selectHandler_user->bind_col( 1, \$user_key);
	$selectHandler_user->bind_col( 2, \$group_key);
	$selectHandler_user->bind_col( 3, \$web_key);
	$selectHandler_user->bind_col( 4, \$btn,{ pg_type => DBD::Pg::PG_BYTEA });

	my @returnUserGroupKeys;
	while ($selectHandler_user->fetch) {
		if($wtexists{join('',$web_key,$btn)}) {
			push(@returnUserGroupKeys,$user_key) if $user_key;
			push(@returnUserGroupKeys,$group_key) if $group_key;
		}
	}
	return \@returnUserGroupKeys;

}

sub fetchSiteAdmin{
	my $this = shift;
	my $site_key = $this->{site_key};
	my $Sites = $this->{database_tables}->{Sites};

	my $selectStatement = qq/SELECT $Sites.admin_user
		FROM $Sites
		WHERE $Sites."key" = '$site_key';/; # site_key
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute;

	my ($admin_key);
	$selectHandler->bind_col( 1, \$admin_key);
	while ($selectHandler->fetch) {
		# TODO: stuff this into some sort of cache
		return $admin_key;
	}


	return undef;
}
# 
sub fetchUserLookupRowByLoginName {
	my $this = shift;
	my $login_name = shift;
	return undef unless $login_name;


	my $site_key = $this->{site_key};
	my $PhoneUser_Lookup = $this->getTableName('PhoneUser_Lookup');

	my $selectStatement = qq^ SELECT $PhoneUser_Lookup.balance, $PhoneUser_Lookup.site_key, $PhoneUser_Lookup.login_name, $PhoneUser_Lookup.user_key, $PhoneUser_Lookup.pin_number, $PhoneUser_Lookup.email FROM $PhoneUser_Lookup WHERE  $PhoneUser_Lookup.site_key = '$site_key' AND $PhoneUser_Lookup.login_name = ? ;^;
	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($login_name);
	my ($balance,$user_key,$pin_number,$email);
	my %user_row;
	$selectHandler->bind_col( 1, \$balance);
	$selectHandler->bind_col( 2, \$site_key);
	$selectHandler->bind_col( 3, \$login_name);
	$selectHandler->bind_col( 4, \$user_key);
	$selectHandler->bind_col( 5, \$pin_number);
	$selectHandler->bind_col( 6, \$email);
	while ($selectHandler->fetch) {
		$user_row{'balance'} = $balance;
		$user_row{'site_key'} = $site_key;
		$user_row{'login_name'} = $login_name;
		$user_row{'user_key'} = $user_key;
		$user_row{'pin_number'} = $pin_number;
		$user_row{'email'} = $email;
	}
	return \%user_row;
}

# for NEW users!
sub insertUser {
	my ($this,$login,$web_name,$topic_name,$password,$emails,$user_topic_key) = @_;

	my (%user_row,%uh_row);
	$uh_row{key} = '';
	$uh_row{login_name} = $login;
	$uh_row{password} = $password;
	$uh_row{user_key} = $this->createUUID(); # same as $cUID
	$uh_row{change_user_key} = '';
	$uh_row{timestamp_epoch} = time();
	$uh_row{email} = $emails;

	my $l2latest = $this->insertUHRow(\%uh_row);

	# insert Users row
	# 1-key, 2-link_to_latest, 3-current_login_name, 4-user_topic_key, 5-site_key
	$user_row{key} = $uh_row{user_key};
	$user_row{link_to_latest} = $l2latest;
	$user_row{current_login_name} = $uh_row{login_name};
	$user_row{user_topic_key} = $user_topic_key;
	$user_row{site_key} = $this->getSiteKey();
	$this->insertUserRow(\%user_row);
	return $user_row{key};
}
sub insertUserRow {
	my ($this,$user_row) = @_;
	my $Users = $this->getTableName('Users');

	$user_row->{site_key} = $this->getSiteKey();
	my $insertStatement_Users = qq^INSERT INTO $Users ("key",link_to_latest, current_login_name, user_topic_key,site_key)
		VALUES (?,?,?,?,?);^; # 1-key, 2-link_to_latest, 3-current_login_name, 4-user_topic_key, 5-site_key
	my $insertHandler_Users = $this->database_connection()->prepare($insertStatement_Users);
	$insertHandler_Users->bind_param( 1, $user_row->{key});
	$insertHandler_Users->bind_param( 2, $user_row->{link_to_latest});
	$insertHandler_Users->bind_param( 3, $user_row->{current_login_name});
	$insertHandler_Users->bind_param( 4, $user_row->{user_topic_key});
	$insertHandler_Users->bind_param( 5, $user_row->{site_key});
	$insertHandler_Users->execute;
	return  $user_row->{key};
}
sub insertUHRow {
	my ($this,$uh_row) = @_;
	my $User_History = $this->getTableName('User_History');

	my $insertStatement_UH = qq^INSERT INTO $User_History ("key",login_name, "password", user_key, change_user_key,timestamp_epoch,email, callback_number, country, first_name, last_name) 
		VALUES (?,?, ? ,?,?,?,?,?,?,?,?);^; 
	# 1-key, 2-login_name, 3-password, 4-user_key,5-change_user_key,6-timestamp_epoch,7-email,8-pin_number,9-country,10-first_name, 11-last_name
	# calculate uh row key
	$uh_row->{change_user_key} ||= $Foswiki::cfg{AdminUserKey};
	$uh_row->{timestamp_epoch} = time();
	$uh_row->{key} = $this->_createUHkey($uh_row);
	my $insertHandler_UH = $this->database_connection()->prepare($insertStatement_UH);
	# insert User_History row
	# 1-key, 2-login_name, 3-password, 4-user_key,5-change_user_key,6-timestamp_epoch,7-email
	$insertHandler_UH->bind_param( 1, $uh_row->{key});
	$insertHandler_UH->bind_param( 2, $uh_row->{login_name});
	$insertHandler_UH->bind_param( 3, $uh_row->{password});
	$insertHandler_UH->bind_param( 4, $uh_row->{user_key});
	$insertHandler_UH->bind_param( 5, $uh_row->{change_user_key});
	$insertHandler_UH->bind_param( 6, $uh_row->{timestamp_epoch});
	$insertHandler_UH->bind_param( 7, $uh_row->{email});
	$insertHandler_UH->bind_param( 8, $uh_row->{callback_number});
	$insertHandler_UH->bind_param( 9, $uh_row->{country});
	$insertHandler_UH->bind_param( 10, $uh_row->{first_name});
	$insertHandler_UH->bind_param( 11, $uh_row->{last_name});

	$insertHandler_UH->execute;
	return $uh_row->{key};

}
# Site Name: $Foswiki::cfg{SiteName}
# According to Freeswitch mod_curl
# Hash = md5_hex($user_name:$site_name:$passwdU); md5_hex
sub changePassword{
	my ($this,$login_name,$passwdU) = @_;

	my $site_key = $this->{site_key};
	my $site_name = $Foswiki::cfg{SiteName};
	die "unholy: $Foswiki::cfg{SiteName}" unless $Foswiki::cfg{SiteName};
	my $Users = $this->getTableName('Users');
	my $UH = $this->getTableName('User_History');

	# DON'T FORGET THE SITE KEY!!!!!!!!!!!!!!!!!!!!!!
	my $Webs = $this->getTableName('Webs');

	my $selectStatement_pw = qq^SELECT u1."key", uh1.change_user_key, uh1.login_name, uh1.last_name, uh1.first_name, uh1.email
		FROM $Users u1 INNER JOIN $UH uh1 ON u1.link_to_latest = uh1."key"
		WHERE u1.site_key = '$site_key' AND u1.current_login_name = ?;^; # 1-login_name

	my $selectHandler_pw = $this->database_connection()->prepare($selectStatement_pw);
	$selectHandler_pw->execute($login_name);


	# TODO: MAKE SURE to fix this later.  The webserver should NEVER see the ciphertext!
	# key =sha1( 1-user_key, 2-change_user_key, 3-timestamp_epoch, 4-login_name, 5-last_name, 6-first_name, 7-email) 
	my (%uh_row);
	my ($user_key,$cuk1,$ln1,$lname,$fname,$email1);
	$selectHandler_pw->bind_col( 1, \$user_key);
	$selectHandler_pw->bind_col( 2, \$cuk1);
	$selectHandler_pw->bind_col( 3, \$ln1);
	$selectHandler_pw->bind_col( 4, \$lname);
	$selectHandler_pw->bind_col( 5, \$fname);
	$selectHandler_pw->bind_col( 6, \$email1);
	while ($selectHandler_pw->fetch) {
		# TODO: stuff this into some sort of cache
		$uh_row{key} = '';
		$uh_row{change_user_key} = $cuk1;
		$uh_row{login_name} = $ln1;
		$uh_row{last_name} = $lname;
		$uh_row{first_name} = $fname;
		$uh_row{email} = $email1;
		$uh_row{user_key} = $user_key;
		return undef unless $user_key;
	}
	$uh_row{password} = md5_hex($login_name.':'.$site_name.':'.$passwdU);
	# prepare to insert
	my $l2latest = $this->insertUHRow(\%uh_row);
	return 1;
}

sub checkPasswordByLoginName {
	my ($this,$login_name,$passwdU) = @_;
	
	my $site_name = $Foswiki::cfg{SiteName};
	my $site_key = $this->{site_key};
	my $Users = $this->getTableName('Users');
	my $UH = $this->getTableName('User_History');
	my $passwdE = md5_hex($login_name.':'.$site_name.':'.$passwdU);
	# DON'T FORGET THE SITE KEY!!!!!!!!!!!!!!!!!!!!!!

	my $selectStatement_pw = qq/SELECT 1
FROM 
  $Users u1 INNER JOIN $UH uh1 ON u1.link_to_latest = uh1."key"
WHERE 
   u1.site_key = '$site_key' AND uh1.login_name = ? AND uh1."password" = ? ;/; # 1-login_name, 2-passwdE, 

	my $selectHandler_pw = $this->database_connection()->prepare($selectStatement_pw);
	$selectHandler_pw->execute($login_name,$passwdE);


	# TODO: MAKE SURE to fix this later.  The webserver should NEVER see the ciphertext!
	my ($answer);
	$selectHandler_pw->bind_col( 1, \$answer);
	while ($selectHandler_pw->fetch) {
		# TODO: stuff this into some sort of cache
		return 0 unless $answer;
	}

	return 1 if $answer;
	return 0;

}


sub _createUHkey {
	my ($this,$uh_row) = @_;

	# key =sha1( 1-user_key, 2-change_user_key, 3-timestamp_epoch, 4-login_name, 5-last_name, 6-first_name, 7-email) 
	# generate user history key
	my $uh_key = substr(sha1_hex( $uh_row->{user_key}, $uh_row->{change_user_key}, $uh_row->{timestamp_epoch}, $uh_row->{login_name},'', '',$uh_row->{email}), 0, - 8);
	$uh_row->{key} = $uh_key;
	return $uh_key;
}

sub _createGHkey {
	my ($this,$gh_row) = @_;

	# key = sha1( 1-group_key, 2-timestamp_epoch,3-user_key, 4-email )  
	# generate group history key
	my $gh_key = substr(sha1_hex( $gh_row->{group_key}, $gh_row->{timestamp_epoch}, $gh_row->{user_key},$gh_row->{email}), 0, - 8);
	$gh_row->{key} = $gh_key;
	return $gh_key;
}
# get list of group names
sub getAllGroups {
	my $this = shift;
	my $site_key = $this->{site_key};

	# get database tables
	my $Groups = $this->getTableName('Groups');
	my $Topics = $this->getTableName('Topics');
	my $BS = $this->getTableName('Blob_Store');
	my $selectStatement = qq/SELECT groups."key", groups.link_to_latest, groups.site_key, bname."value"
		FROM 
		  $Topics topics
			INNER JOIN $Groups groups ON groups.group_topic_key = topics."key"
			INNER JOIN $BS bname ON bname."key" = topics.current_topic_name
		WHERE groups.site_key = '$site_key';/;

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute;

	my @return_array = ();
	my ($group_key);
	$selectHandler->bind_col( 1, \$group_key);
	while ($selectHandler->fetch) {
		# TODO: stuff this into some sort of cache
		push(@return_array,$group_key);
	}
	return \@return_array;
}

# get list of user keys
sub getGroupMembers {
	my $this = shift;
	my ($group_key,$webtopic) = @_;
	
	my @fetcherInput = ($webtopic);
	my $site_key = $this->{site_key};
	unless($group_key){
		my $arrayref = $this->fetchcUIDOrGroupKeyByWikiName(@fetcherInput);
		$group_key = $arrayref->[0];
	}
	return undef unless $group_key;

	# get database tables
	my $GU = $this->getTableName('Group_User_Membership');
	my $selectStatement = qq/SELECT 
  gu.user_key
FROM 
  $GU gu 
WHERE
  gu.group_key = ? ;/;

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($group_key);

	my @return_array = ();
	my ($user_key);
	$selectHandler->bind_col( 1, \$user_key);
	while ($selectHandler->fetch) {
		# TODO: stuff this into some sort of cache
		push(@return_array,$user_key);
	}
	return \@return_array;
}

# get list of group names ($cUID)
sub getUserMembers {
	my $this = shift;
	my ($cUID) = @_;
	return undef unless $cUID;
	# check local cache
	my $garray = $this->{user_cache}->{'groups'.$cUID};
	return $garray if $this->{user_cache}->{'groups'.$cUID.'scooped'};
	
	# get database tables
	my $GU = $this->getTableName('Group_User_Membership');
	my $selectStatement = qq/SELECT 
  gu.group_key
FROM 
  $GU gu 
WHERE
  gu.user_key = ? ;/;

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($cUID);

	my @return_array = ();
	my ($group_key);
	$selectHandler->bind_col( 1, \$group_key);
	while ($selectHandler->fetch) {
		# TODO: stuff this into some sort of cache
		push(@return_array,$group_key);
	}
	# load the results into the cache
	$this->{user_cache}->{'groups'.$cUID.'scooped'} = 1;
	$this->{user_cache}->{'groups'.$cUID} = \@return_array;
	
	return \@return_array;
}
=pod
For creating new groups

INSERT INTO $Groups ("key", link_to_latest, site_key, group_topic_key) VALUES (?,?,?,?);


INSERT INTO $GH ("key", group_name, group_key, email, timestamp_epoch, user_key) VALUES (?,?,?,?,?,?);


=cut
sub insertGHRow {
	my ($this,$ghrow) = @_;

	# key = sha1( 1-group_key, 2-timestamp_epoch,3-user_key, 4-email )  
	my $GH = $this->getTableName('Group_History');
	my $insertStatement = qq^INSERT INTO $GH ("key", group_name, group_key, email, timestamp_epoch, user_key) VALUES 			(?,?,?,?,?,?);^;
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->bind_param( 1, $ghrow->{key});
	$insertHandler->bind_param( 2, $ghrow->{group_name});
	$insertHandler->bind_param( 3, $ghrow->{group_key});
	$insertHandler->bind_param( 4, $ghrow->{email});
	$insertHandler->bind_param( 5, $ghrow->{timestamp_epoch});
	$insertHandler->bind_param( 6, $ghrow->{user_key});
	$insertHandler->execute;
	return  $ghrow->{key};	
}
sub insertGroupRow {
	my ($this,$grouprow) = @_;

	my $Groups = $this->getTableName('Groups');
	$grouprow->{site_key} = $this->getSiteKey();

	my $insertStatement = qq^INSERT INTO $Groups ("key", link_to_latest, site_key, group_topic_key) VALUES (?,?,?,?);^;

	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	$insertHandler->bind_param( 1, $grouprow->{key});
	$insertHandler->bind_param( 2, $grouprow->{link_to_latest});
	$insertHandler->bind_param( 3, $grouprow->{site_key});
	$insertHandler->bind_param( 4, $grouprow->{group_topic_key});
	$insertHandler->execute;
	return  $grouprow->{key};
}


# generate sha1_hex of site key and time in order to generate a password
sub generateRandomPassword {
	my $this = shift;
	return sha1_hex(time(),$this->{site_key});
}
# ($user_key)
sub loadUHRowByUserKey {
	my ($this,$user_key) = @_;
	my $User_History = $this->getTableName('User_History');
	my $Users = $this->getTableName('Users');

	my $selectStatement = qq^SELECT uh1."key", uh1.first_name, uh1.last_name,
  uh1.login_name, uh1."password", uh1.user_key, uh1.change_user_key, uh1.timestamp_epoch, uh1.email, uh1.callback_number, uh1.country
FROM 
  $User_History uh1
	INNER JOIN $Users u1 ON uh1."key" = u1.link_to_latest
WHERE 
  u1."key" = ?;^; # 1-key

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	$selectHandler->execute($user_key);
	my $user_hash;
	my ( $key, $first_name, $last_name, $login_name, $password, $Duser_key, $change_user_key, $timestamp_epoch, $email, $pin_number, $country,$call_back_number);
	$selectHandler->bind_col( 1, \$key );
	$selectHandler->bind_col( 2, \$first_name );
	$selectHandler->bind_col( 3, \$last_name );
	$selectHandler->bind_col( 4, \$login_name );
	$selectHandler->bind_col( 5, \$password );
	$selectHandler->bind_col( 6, \$Duser_key );
	$selectHandler->bind_col( 7, \$change_user_key );
	$selectHandler->bind_col( 8, \$timestamp_epoch );
	$selectHandler->bind_col( 9, \$email );
	$selectHandler->bind_col( 10, \$call_back_number );
	$selectHandler->bind_col( 11, \$country );
	

	while ($selectHandler->fetch) {
		$user_hash->{key} = $key;
		$user_hash->{first_name} = $first_name;
		$user_hash->{last_name} = $last_name;
		$user_hash->{login_name} = $login_name;
		$user_hash->{password} = $password;
		$user_hash->{user_key} = $Duser_key;
		$user_hash->{change_user_key} = $change_user_key;
		$user_hash->{timestamp_epoch} = $timestamp_epoch;
		$user_hash->{email} = $email;
		$user_hash->{callback_number} = $call_back_number;
		$user_hash->{country} = $country;
		return $user_hash;
	}
	return undef;
}

1;
__END__

