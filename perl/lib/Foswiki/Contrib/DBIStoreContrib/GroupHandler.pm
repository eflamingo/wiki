# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::GroupHandler;

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
use base ("Foswiki::Contrib::DBIStoreContrib::UserHandler");

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


# () -> @allgroups (group_keys)
sub getAllGroups {
	my $this = shift;
	my $site_key = $this->{site_key};

	# get database tables
	my $Groups = $this->{database_tables}->{Groups};

	my $selectStatement_group = qq/SELECT $Groups."key" FROM $Groups WHERE $Groups.site_key = '$site_key' ;/; 

	my $selectHandler_group = $this->database_connection()->prepare($selectStatement_group);
	$selectHandler_group->execute;

	my @return_array = ();
	my ($group_key);
	$selectHandler_group->bind_col( 1, \$group_key);
	while ($selectHandler_group->fetch) {
		# TODO: stuff this into some sort of cache
		push(@return_array,$group_key);
	}
	return \@return_array;
}

# (group_key OR! group_name) -> @list_of_user_keys (members of the group)
sub getGroupMembers {
	my $this = shift;
	my ($group_key,$group_name) = @_;
	my $site_key = $this->{site_handler}->{site_key};

	my $Groups = $this->{database_tables}->{Groups};
	my $Users = $this->{database_tables}->{Users};
	my $Group_User_Membership = $this->{database_tables}->{Group_User_Membership};

	# derive the WHERE statement, which depends on whether $group_key or $group_name was supplied
	# based on the group_name
	my $where_seg;
	if($group_key){
		$where_seg = qq/WHERE $Groups."key" = ?/; # 1-group_key
	}
	else{
		return undef unless $group_name;
		my $topic_hunter = $this->{hunter}->{topic_hunter}; # 1-web_name, 2-topic_name
		$where_seg = qq/WHERE $Groups.group_topic_key = ($topic_hunter)/;
	}
	# cannot allow nested groups
	my $selectStatement_users = qq/SELECT   $Users."key"
		FROM 
		$Group_User_Membership 
		INNER JOIN $Users ON $Users."key" = $Group_User_Membership.user_key
		INNER JOIN $Groups ON $Groups."key" = $Group_User_Membership.group_key
		$where_seg;/; # 1-group_key

	my $selectHandler_users = $this->database_connection()->prepare($selectStatement_users);
	# again, the bind_param depends on whether group_key was supplied or group_name
	if($group_key){
		$selectHandler_users->bind_param( 1, $group_key);
	}
	else{
		my ($gweb_name,$gtopic_name) = Foswiki::Func::normalizeWebTopicName($Foswiki::cfg{UsersWebName},$group_name);
		$selectHandler_users->bind_param( 1, $gweb_name);
		my $bytea_topic_name = sha1($gtopic_name);
		$selectHandler_users->bind_param( 2, $bytea_topic_name,{ pg_type => DBD::Pg::PG_BYTEA });
	}
	
	$selectHandler_users->execute;

	my @return_array = ();
	my ($user_key);
	$selectHandler_users->bind_col( 1, \$user_key);
	while ($selectHandler_users->fetch) {
		# TODO: stuff this into some sort of cache
		push(@return_array,$user_key);
	}
	return \@return_array;

}

# (user_key) -> @allgroups (group_keys) that the user is a member of
sub getListOfGroupsBycUID {
	my $this = shift;
	my $user_key = shift;
	my $site_key = $this->{site_handle}->{site_key};

	# get database tables
	my $Groups = $this->{database_tables}->{Groups};
	my $Users = $this->{database_tables}->{Users};
	my $Group_User_Membership = $this->{database_tables}->{Group_User_Membership};

	my $selectStatement_group = qq/SELECT $Group_User_Membership.group_key
		FROM $Group_User_Membership WHERE $Users."key" = ?;/; # 1-user_key

	my $selectHandler_group = $this->database_connection()->prepare($selectStatement_group);
	$selectHandler_group->execute;

	my @return_array = ();
	my ($group_key);
	$selectHandler_group->bind_col( 1, \$group_key);
	while ($selectHandler_group->fetch) {
		# TODO: stuff this into some sort of cache
		push(@return_array,$group_key);
	}
	return \@return_array;
}

# getWikiName_User(cUID) -> { web_name => Main, topic_name => 'Admin'} hash return
sub getWikiName_Group {
	my $this = shift;
	my $group_key = shift;
	# make sure that the input is a GUID
	$group_key = $this->checkUUID($group_key);
	return undef unless $group_key;

	# get database tables
	my $Groups = $this->getTableName('Groups');
	my $BS = $this->getTableName('Blob_Store');
	my $Topics = $this->getTableName('Topics');
	my $Webs = $this->getTableName('Webs');

	my $selectStatement = qq/SELECT 
  w1.current_web_name, 
  tname."value"
FROM 
  $Topics t1
	INNER JOIN $BS tname ON t1.current_topic_name = tname."key"
	INNER JOIN $Groups g1 ON t1."key" = g1.group_topic_key
	INNER JOIN $Webs w1 ON t1.current_web_key = w1."key"
WHERE 
  g1."key" = ? ;/; # 1-group_key

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	
	$selectHandler->execute($group_key);

	my %return_hash;
	my ($web_name,$topic_name);
	$selectHandler->bind_col( 1, \$web_name);
	$selectHandler->bind_col( 2, \$topic_name);
	while ($selectHandler->fetch) {
		# TODO: stuff this into some sort of cache
		$return_hash{web_name} = $web_name;
		$return_hash{topic_name} = $topic_name;
		return \%return_hash;
	}

	return undef;
}

# getGroupKeyByWT(cUID) -> { web_name => Main, topic_name => 'Admin'} hash return
sub getGroupKeyByWT {
	my $this = shift;
	my $group_key = shift;
	# make sure that the input is a GUID
	$group_key = $this->checkUUID($group_key);
	return undef unless $group_key;

	# get database tables
	my $Groups = $this->getTableName('Groups');
	my $BS = $this->getTableName('Blob_Store');
	my $Topics = $this->getTableName('Topics');
	my $Webs = $this->getTableName('Webs');

	my $selectStatement = qq/SELECT 
  w1.current_web_name, 
  tname."value"
FROM 
  $Topics t1
	INNER JOIN $BS tname ON t1.current_topic_name = tname."key"
	INNER JOIN $Groups g1 ON t1."key" = g1.group_topic_key
	INNER JOIN $Webs w1 ON t1.current_web_key = w1."key"
WHERE 
  g1."key" = ? ;/; # 1-group_key

	my $selectHandler = $this->database_connection()->prepare($selectStatement);
	
	$selectHandler->execute($group_key);

	my %return_hash;
	my ($web_name,$topic_name);
	$selectHandler->bind_col( 1, \$web_name);
	$selectHandler->bind_col( 2, \$topic_name);
	while ($selectHandler->fetch) {
		# TODO: stuff this into some sort of cache
		$return_hash{web_name} = $web_name;
		$return_hash{topic_name} = $topic_name;
		return \%return_hash;
	}

	return undef;
}
# insertUGRowByTopicKey(\@user_keys,$topic_key)-> nothing, just delete all of the old pairs, and add new pairs
sub insertUGRowByTopicKey {
	my ($this,$user_refs,$topic_key) = @_;
	my $Groups = $this->getTableName('Groups');
	my $UG = $this->getTableName('Group_User_Membership');
	my $site_key = $this->getSiteKey();
	my @user_keys = @{$user_refs};
	my @QuestionPads;
	foreach my $ukey01 (@user_keys) {
		push( @QuestionPads , '?');
	}
	
	my $QuestionString = join(',',@QuestionPads);
	my $deleteStatement = qq/DELETE FROM $UG ug1 WHERE EXISTS (
	 SELECT g1."key" FROM $Groups g1 WHERE g1."key" = ug1.group_key AND g1.group_topic_key = ?  AND ug1.user_key NOT IN ($QuestionString) );/; # 1-group_topic_key, 2+ ?,?,?,...,?
	my $deleteHandler = $this->database_connection()->prepare($deleteStatement);
	$deleteHandler->execute($topic_key,@user_keys);
	my $insertStatement = qq/ SELECT foswiki.insert_ug_new( ? , g1."key") FROM $Groups g1 WHERE g1.group_topic_key = ? ;/; # 1-user_key 2-group_topic_key
	my $insertHandler = $this->database_connection()->prepare($insertStatement);
	foreach my $ukey02 (@user_keys) {
		$insertHandler->execute($ukey02,$topic_key);
	}
	return 1;
}

1;
__END__

