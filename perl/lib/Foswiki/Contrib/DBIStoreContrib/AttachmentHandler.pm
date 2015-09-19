# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::AttachmentHandler;

use strict;
use warnings;

#use Exporter 'import';
#@EXPORT_OK = qw(LoadTopicRow); # symbols to export on request

use Assert;


#use Pg		();

use IO::File   ();
use DBI	       ();

use File::Copy ();
use File::Spec ();
use File::Path ();

use IO::Scalar ();

use Fcntl    qw( :DEFAULT :flock SEEK_SET );
use DBI				    ();
use DBD::Pg			    ();
use Data::UUID			    ();
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);

use File::Slurp qw(write_file);
use DBI qw(:sql_types);

use File::Basename ();

use File::Path qw(make_path remove_tree); #was fragged in Ubuntu update

use Foswiki::Contrib::DBIStoreContrib::ResultSetAttachment ();



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

# ($web,$topic,$attachment) -> Attachment_key
sub fetchAttachmentKeyByWTA{
	my ($this,$web_name,$topic_name,$attachment_name) = @_;
	my $wta = join('&',$web_name,$topic_name,$attachment_name);
	my $attachment_key = $this->{attachment_cache}->{$wta};
	return $attachment_key if $attachment_key;
	
	# let's check memcached before we give up
	$attachment_key = $this->fetchMemcached('attachment_cache',$wta);
	return $attachment_key;
}

# ($attachment_key) -> Attachments.* row fetcher
sub fetchAttachmentRowByAttachmentKey{
	my ($this,$attachment_key) = @_;
	my $arow = $this->{attachment_cache}->{$attachment_key};
	return $arow if $arow;

	# let's check memcached before we give up
	$arow = $this->fetchMemcached('attachment_cache',$attachment_key);
	return $arow;
}
# ($web,$topic,$attachment) -> Attachments.* row
sub fetchAttachmentRowByWTA{
	my ($this,$web_name,$topic_name,$attachment_name) = @_;
	my $attachment_key = $this->fetchAttachmentKeyByWTA($web_name,$topic_name,$attachment_name);
	return undef unless $attachment_key;
	return $this->fetchAttachmentRowByAttachmentKey($attachment_key);

}
# ($web,$topic,$attachment,$version) -> AH_key
sub fetchAHKeyByWTAR{
	my ($this,$web_name,$topic_name,$attachment_name,$version) = @_;
	return undef unless $web_name && $topic_name && $attachment_name;
	$version = '-1' unless $version;
	my $attachment_key = $this->fetchAttachmentKeyByWTA($web_name,$topic_name,$attachment_name);
	return $attachment_key if $attachment_key;
	
	my $ah_key = $this->{attachment_cache}->{$attachment_key.$version};
	return $ah_key if $ah_key;
	# let's check memcached before we give up
	$ah_key = $this->fetchMemcached('attachment_cache',$attachment_key.$version);
	return $ah_key;
}
# ($web,$topic,$attachment,$version) -> AH.* row
sub fetchAHRowByAHKey{
	my ($this,$ah_key) = @_;
	my $ahrow = $this->{attachment_cache}->{$ah_key};
	return $ahrow if $ahrow;
	
	# let's check memcached before we give up
	$ahrow = $this->fetchMemcached('attachment_cache',$ah_key);
	return $ahrow;
}
# ($web,$topic,$attachment,$version) -> AH.* row
sub fetchAHRowByWTAR{
	my ($this,$web_name,$topic_name,$attachment_name,$version) = @_;
	my $ahkey = $this->fetchAHKeyByWTAR($web_name,$topic_name,$attachment_name,$version);
	return undef unless $ahkey;
	return $this->fetchAHRowByAHKey($ahkey);	
}
############################################################################################
########################          Putting Functions            #############################
############################################################################################


# ($web,$topic,$attachment) -> Attachment_key
sub putAttachmentKeyByWTA{
	my ($this,$web_name,$topic_name,$attachment_name,$attachment_key) = @_;
	return undef unless $web_name && $topic_name && $attachment_name && $attachment_key;
	my $wta = join('&',$web_name,$topic_name,$attachment_name);
	$this->{attachment_cache}->{$wta} = $attachment_key;
	
	# let's load it into memcache too
	# 60 sec b/c we are mapping web.topic to a key, which is prone to frequent change
	$this->putMemcached('attachment_cache',$wta,$attachment_key,60);
	
	return $attachment_key
}

# ($attachment_key) -> Attachments.* row 
sub putAttachmentRowByAttachmentKey{
	my ($this,$attachment_key, $arow) = @_;
	return undef unless $attachment_key && $arow;
	$this->{attachment_cache}->{$attachment_key} = $arow;
	
	# let's load it into memcache too
	$this->putMemcached('attachment_cache',$attachment_key,$arow);
	return $arow;
}

# ($web,$topic,$attachment,$version) -> AH_key  Version is assumed to be '-1' (link_to_latest) unless stated otherwise
sub putAHKeyByWTAR{
	my ($this,$web_name,$topic_name,$attachment_name,$version,$ah_key) = @_;
	return undef unless $web_name && $topic_name && $attachment_name && $ah_key;
	$version = '-1' unless $version;
	my $wta = join('&',$web_name,$topic_name,$attachment_name);
	my $attachment_key = $this->fetchAttachmentKeyByWTA($web_name,$topic_name,$attachment_name);
	return undef unless $attachment_key && $version && $ah_key;
	$this->{attachment_cache}->{$attachment_key.$version} = $ah_key;

	# let's load it into memcache too
	$this->putMemcached('attachment_cache',$attachment_key.$version,$ah_key);
	
	return $ah_key;
	
}
# ($web,$topic,$attachment,$version) -> AH_key
sub putAHRowByAHKey{
	my ($this,$ah_key,$ahrow) = @_;
	return undef unless $ah_key && $ahrow;
	$this->{attachment_cache}->{$ah_key} = $ahrow;
	
	# let's load it into memcache too
	$this->putMemcached('attachment_cache',$ah_key,$ahrow);
	
	return $ahrow;
}

############################################################################################
########################          SQL Select Functions         #############################
############################################################################################

# ($web_name,$topic_name,$attachment_name,$version) -> $row_data->{field} with all fields returned
sub LoadAHRow {
	my ($this,$web_name,$topic_name,$attachment_name,$version) = @_;
	my $site_key = $this->{site_key};
	my $bytea_topic_name = sha1($topic_name);
	my ($file_name,$dir_empty01,$file_type) = File::Basename::fileparse($attachment_name,qr/\.[^.]*/);
	$file_type =~ s/^\.//;  # strip the . from the front of the file extension
	return undef unless $file_name && $file_type;  # need to check these
	#print "topichandler::LoadAHRow()\n";
	### First, check if it is already in the cache ###
	my $row_data = $this->fetchAHRowByWTAR($web_name,$topic_name,$attachment_name,$version);
	my $boolean = 1;
## old line 01
	my @ahfieldList = @{ $this->getColumnNameList('Attachment_History') };
	foreach my $field_ref (@ahfieldList) {
		$boolean = 0 unless $row_data->{$field_ref};
	}
	return $row_data if $boolean;  # returns the row_ref in the cache if all fields exist in the cache
	# clean out row_ref so that we can use it later
	$row_data = {};
	######## The rest is assuming the th_row is not in the cache
	# since it is a select statement, let's do autocommit
	$this->database_connection()->{AutoCommit} = 1;
	# Name all of the database tables
	my $Webs = $this->getTableName('Webs');
	my $Topic_History = $this->getTableName('Topic_History');
	my $Topics = $this->getTableName('Topics');
	my $Attachment_History = $this->getTableName('Attachment_History');
	my $Attachments = $this->getTableName('Attachments');
	my $FS = $this->getTableName('File_Store');
	my $topic_hunter = $this->{hunter}->{topic_hunter};
## old line 02
	# select part
	my $select_part = qq/SELECT ah."key", ah.topic_key, ah."version", ah.path, ah.timestamp_epoch, ah.user_key, ah.attr, ah.file_name, ah.file_type, 
  					ah.blob_store_key, ah.file_store_key, ah."comment", ah.attachment_key, fs.size, fs.file_blob /;
	# no version
	my $selectStatement_th_noVer = qq/$select_part
	FROM $Attachment_History ah
	INNER JOIN $FS fs ON ah.file_store_key = fs."key"
	INNER JOIN $Attachments a1 ON ah.attachment_key = a1."key"
		WHERE a1.current_topic_key = ($topic_hunter) AND ah.file_name = ? AND ah.file_type = ? ;/ unless $version;
	# version
	my $selectStatement_th_Ver = qq/$select_part
  		FROM $Attachment_History ah
		INNER JOIN $FS fs ON ah.file_store_key = fs."key"
			WHERE ah.topic_key = ($topic_hunter) AND  ah.file_name = ? AND ah.file_type = ? AND ah."version" = ? ;/ if $version;

	my ($ah_key,$attachment_key,$aver,$ah_handle);
	if($version){
		# 1-web_name, 2-topic_name, 3-revision
		$ah_handle = $this->database_connection()->prepare($selectStatement_th_Ver);
		$ah_handle->bind_param( 1, $web_name);
		$ah_handle->bind_param( 2, $bytea_topic_name,{ pg_type => DBD::Pg::PG_BYTEA });
		$ah_handle->bind_param( 3, $file_name);
		$ah_handle->bind_param( 4, $file_type);
		$ah_handle->bind_param( 5, $version);
		$ah_handle->execute;	
	}
	else {
		# 1-web_name, 2-topic_name
		$ah_handle = $this->database_connection()->prepare($selectStatement_th_noVer);
		$ah_handle->bind_param( 1, $web_name);
		$ah_handle->bind_param( 2, $bytea_topic_name,{ pg_type => DBD::Pg::PG_BYTEA });
		$ah_handle->bind_param( 3, $file_name);
		$ah_handle->bind_param( 4, $file_type);
		$ah_handle->execute;
	}

# old line 03
# 1-ah."key", 2-ah.topic_key, 3-ah."version", 4-ah.path, 5-ah.timestamp_epoch, 6-ah.user_key, 7-ah.attr, 8-ah.file_name, 9-ah.file_type, 
#  					10-ah.blob_store_key, 11-ah.file_store_key, 12-ah."comment", 13-ah.attachment_key, 14-fs.size, 15-fs.file_blob
	my $field_list_length = scalar(@ahfieldList);
	my @return_list;
	for (my $count = 1; $count <= $field_list_length; $count++) {
		$ah_handle->bind_col($count, \$return_list[$count-1] ) unless $count == 10 || $count == 12;
		$ah_handle->bind_col($count, \$return_list[$count-1] ,{ pg_type => DBD::Pg::PG_BYTEA }) if $count == 10 || $count == 12;
	}
# old line 04
	while ($ah_handle->fetch) {
		# Only one row should be returned.
		for (my $count2 = 1; $count2 <= $field_list_length; $count2++) {
			$row_data->{$ahfieldList[$count2-1]} = $return_list[$count2-1];
			$ah_key = $return_list[$count2-1] if $count2 == 1;
			$attachment_key = $return_list[$count2-1] if $count2 == 13;
			$aver = $return_list[$count2-1] if $count2 == 3;
		}

	}
# old line 05

	
	# put some data in the cache

	# if no version is specified, the latest ah_row is assumed

	# ($web,$topic,$attachment) -> attachment_key
	$this->putAttachmentKeyByWTA($web_name,$topic_name,$attachment_name,$attachment_key);
# old line 06
	# ($web,$topic,$attachment,$version) -> attachment_history_key
	$this->putAHKeyByWTAR($web_name,$topic_name,$aver,$ah_key) if $aver; # for revision
	$this->putAHKeyByWTAR($web_name,$topic_name,$attachment_name,'-1',$ah_key) unless $version; # for link to latest
# old line 07

	# Sets  ($th_key) -> Topic_History.* row mapping
	$this->putAHRowByAHKey($ah_key,$row_data);

	return $row_data;

}
# ($topic_key)->\@returnedAHRows array of hashes
sub LoadAllAttachmentsByTopicKey {

	my ($this,$topic_key) = @_;
	my $site_key = $this->{site_key};
	my $AH = $this->getTableName('Attachment_History');
	my $Attachments = $this->getTableName('Attachments');
	my $FS = $this->getTableName('File_Store');
	my $BS = $this->getTableName('Blob_Store');
	my $topic_hunter = $this->{hunter}->{topic_hunter}; # 1-web_name, 2-topic_name
	my $selectStatement = qq/SELECT ah."key", ah.topic_key, ah."version", ah.timestamp_epoch, ah.user_key, ah.file_name, 
		ah.file_type, ah.attachment_key, bcomment."value", fs.file_blob, fs.size
FROM 
  $AH ah 
	INNER JOIN $FS fs ON fs."key" = ah.file_store_key
	INNER JOIN $Attachments a1 ON a1.link_to_latest = ah."key"
	INNER JOIN $BS bcomment ON bcomment."key" = ah."comment"
WHERE 
  ah.topic_key = ?;/; # 1- topic_key
	my $ah_handle = $this->database_connection()->prepare($selectStatement);
	$ah_handle->execute($topic_key);
	#  1-ah."key", 2-ah.topic_key, 3-ah."version", 4-ah.timestamp_epoch, 5-ah.user_key, 6-ah.file_name, 
			# 7-ah.file_type, 8-ah.attachment_key, 9-bcomment."value", 10-fs.file_blob, 11-fs.size
	my @colarray = ('key','topic_key','version','timestamp_epoch','user_key','file_name','file_type','attachment_key','comment','file_blob','size');
	return $ah_handle->fetchall_arrayref;
	
}
# ($attachment_key) -> \@array of attachment rows aka revisions of this attachment
sub loadAllRevisionsByAttachmentKey {
	my ($this,$attachment_key) = @_;
	my $site_key = $this->{site_key};
	my $AH = $this->getTableName('Attachment_History');
	my $Attachments = $this->getTableName('Attachments');
	my $FS = $this->getTableName('File_Store');
	my $BS = $this->getTableName('Blob_Store');
	my $selectStatement = qq/SELECT ah."key", ah.topic_key, ah."version", ah.timestamp_epoch, ah.user_key, ah.file_name, 
		ah.file_type, ah.attachment_key, bcomment."value", fs.file_blob, fs.size
FROM 
   $AH ah 
	INNER JOIN $FS fs ON fs."key" = ah.file_store_key
	INNER JOIN $BS bcomment ON bcomment."key" = ah."comment"
WHERE 
  ah.attachment_key = ?;/; # 1- attachment_key
	my $ah_handle = $this->database_connection()->prepare($selectStatement);
	$ah_handle->execute($attachment_key);
	#  1-ah."key", 2-ah.topic_key, 3-ah."version", 4-ah.timestamp_epoch, 5-ah.user_key, 6-ah.file_name, 
			# 7-ah.file_type, 8-ah.attachment_key, 9-bcomment."value", 10-fs.file_blob, 11-fs.size
	my @colarray = ('key','topic_key','version','timestamp_epoch','user_key','file_name','file_type','attachment_key','comment','file_blob','size');
	
	# put some sort of caching stuff here
	return $ah_handle->fetchall_arrayref;	
}
sub _GetFileFromDB {
	my ( $this,$web_name,$topic_name,$attachment_name, $mode, $version) = @_;
	my $success;
	$version = '' unless defined($version);
	my $site_key = $this->{site_key};
	# ($topic,$web,$attachment,$revision) -> $row_data->{field} with all fields returned
	my $ah_row = $this->LoadAHRow($web_name,$topic_name,$attachment_name,$version);
	my $file_key = $ah_row->{file_store_key};
	my $lobjId = $ah_row->{file_blob};
	warn "File Key: $file_key for ($web_name,$topic_name,$attachment_name)\n";

	# create a space for the file to be written to
	my $file_directory = $Foswiki::cfg{PubDir}.'/FileStore/'.$this->_getSubFileDirectoryByHash($file_key);
	$this->_doMkdirFullPath($file_directory);



	# get the file from Amazon, save it to the FileStore directory
	# save it from amazon and feed the scalar back to the user
	require Foswiki::Contrib::DBIStoreContrib::AmazonS3;
	my $s3 = Foswiki::Contrib::DBIStoreContrib::AmazonS3::->new($this->getSiteKey());
	my $file_raw = $s3->fetch_keyvalue($ah_row->{key},$this->getSiteKey());
	# return the entire file as a scalar
	#die "length:".length($file_raw);
	return $file_raw;




	# get the file from the DB
	my $DB_name = $Foswiki::cfg{Store}{DBI}{database_name};
	my $DB_host = $Foswiki::cfg{Store}{DBI}{database_host};
	my $DB_user = $Foswiki::cfg{Store}{DBI}{database_user_ah};
	my $DB_pwd = $Foswiki::cfg{Store}{DBI}{database_password_ah};

	my $pgconnection = Pg::setdbLogin($DB_host, '5432', "", "", $DB_name, $DB_user, $DB_pwd);


	my $BUFSIZE = 8192;
	# this function should write the file to the file_directory location
	$pgconnection->exec("begin");
	$success = $pgconnection->lo_export($lobjId, $file_directory);
	warn "lo_export: $success of $lobjId\n $file_directory\n";
	$pgconnection->exec("end");
	return undef if $success == -1;


	# create a sym link
	# 1-site_key, 2-web, 3-topic, 4-attachment
	my $FileNameHash = sha1_hex($site_key,$web_name,$topic_name,$attachment_name,$version);
	my $symlinkpath = $Foswiki::cfg{PubDir}.'/SymLinks/'.$this->_getSubFileDirectoryByHash($FileNameHash);
	$this->_doMkdirFullPath($symlinkpath);
	return undef unless eval { symlink($file_directory,$symlinkpath); 1 };
	return $success;


}

sub openStreamByWTAR {
	my ($this,$web_name,$topic_name,$attachment_name,$version,$mode) = @_;
	$version = '' unless defined($version);
	
	return undef if $mode ne '<';
	my $site_key = $this->{site_key};
	# generate the hash key to get the file
	# 1-site_key, 2-web, 3-topic, 4-attachment
	my $FileNameHash = sha1_hex($site_key,$web_name,$topic_name,$attachment_name,$version);
	my $symfiledir = $Foswiki::cfg{PubDir}.'/SymLinks/'.$this->_getSubFileDirectoryByHash($FileNameHash);
	$this->_doMkdirFullPath($symfiledir);
	my $stream;
	
	my $ahrow = $this->LoadAHRow($web_name,$topic_name,$attachment_name,$version);
	# if not, get it from the database and check again
	my $file_scalar = $this->_GetFileFromDB($web_name,$topic_name,$attachment_name, $mode, $version);
	$stream = new IO::Scalar \$file_scalar;	
	return $stream;

	my $file_store_key = $ahrow->{file_store_key};
	return undef unless $file_store_key;
	my $file_key_dir = $Foswiki::cfg{PubDir}.'/FileStore/'.$this->_getSubFileDirectoryByHash($file_store_key);



	# if not, get it from the database and check again
	my $file_scalar = $this->_GetFileFromDB($web_name,$topic_name,$attachment_name, $mode, $version);
	$stream = new IO::Scalar \$file_scalar;	
	return $stream;
	#.........nothing below this is executed.......................#



	#warn "WTA ($web_name,$topic_name,$attachment_name,$version)\n";
	if(-f $file_key_dir){
		# check to see if it is in the file system

		unless( open($stream, $mode ,$file_key_dir) ){
			#warn "failed to open file (part 1)\n";
		}
		binmode $stream;

		return $stream;		
	}
	else{
		# if not, get it from the database and check again
		my $file_scalar = $this->_GetFileFromDB($web_name,$topic_name,$attachment_name, $mode, $version);		
		unless( open($stream, $mode, \$file_scalar) ){
			#warn
		}
		binmode $stream;
		return $stream;

		# try to get the file again
		unless( open($stream, $mode ,$file_key_dir) ){
			#warn "failed to open file (part 2)\n";
		}
		binmode $stream;
		return $stream;		
	}


}

# Copies attachment to proper locations
sub saveStream {
	my ( $this, $ref ) = @_;
	my $ahrow = $ref->{attachment_row};
	my $site_key = $this->getSiteKey();
	my $fh = $ref->{stream};
	my $size = $ref->{size};
	ASSERT($fh) if DEBUG;
	# write the temp file to the working directory
	my $temp_location = $this->createUUID;
	my $fspath = $Foswiki::cfg{WorkingDir}.'/tmp/'.$temp_location;
	$this->_doMkdirFullPath($fspath);
	# file $F is empty
	my $F;
	open( $F, '>', $fspath )
		|| throw Error::Simple('DBIStoreContrib::AttachmentHandler: open ' . $fspath . ' failed: ' . $! );
	binmode($F)
		|| throw Error::Simple('DBIStoreContrib::AttachmentHandler: failed to binmode ' . $fspath . ': ' . $! );

	my $buffer;
	my ($keyfile,$byte_size);
	$byte_size = 0;
	while ( read( $fh, $buffer, 1024 ) ) {
		# this writes data directly into postgres big object database
		$byte_size += length($buffer);
		# write the stream from the user into the temp file $F
		print $F $buffer;
		# this writes the stream from the user into Memory
		$keyfile .= $buffer;		
	}
	close($F)  || throw Error::Simple('DBIStoreContrib::AttachmentHandler: close ' . $fspath . ' failed: ' . $! );

	my $file_store_key = sha1_hex($keyfile);
	# put the file into Amazon
	#.... we need the site_key and the ah_key
	#.... key = sha1( 1-file_name, 2-file_type, 3-size, 4-timestamp_epoch, 5-file_store_key, 6-user_key, 7-topic_key, 8-attachment_key)
	my $file_size = $byte_size;
	$ahrow->{size} = $file_size;
	$ahrow->{file_store_key} = $file_store_key;
	$ahrow->{key} = $this->_createAHkey($ahrow);
	# save it to amazon
	require Foswiki::Contrib::DBIStoreContrib::AmazonS3;
	my $s3 = Foswiki::Contrib::DBIStoreContrib::AmazonS3::->new($this->getSiteKey());
	# we need to check for hyphens in the guid $file_store_key
	if($ahrow->{key} =~ m/^(\{{0,1}([0-9a-fA-F]){8}-([0-9a-fA-F]){4}-([0-9a-fA-F]){4}-([0-9a-fA-F]){4}-([0-9a-fA-F]){12}\}{0,1})$/){
		# then, no need to do anything
	}
	elsif($ahrow->{key} =~ m/^([0-9a-fA-F]{8})([0-9a-fA-F]{4})([0-9a-fA-F]{4})([0-9a-fA-F]{4})([0-9a-fA-F]{12})$/) {
		# add hyphens, b/c all Amazon S3 objects encrypted with hyphened guid
		my @simple_arr = ($1,$2,$3,$4,$5);
		$ahrow->{key} = join('-',@simple_arr);
	}
	$s3->save_keyvalue($ahrow->{key},$keyfile,$this->getSiteKey());
	#$this->insertFileStoreRow($file_store_key,$file_size);
=pod
	# create large object in postgres
	# get the file from the DB
	my $DB_name = $Foswiki::cfg{Store}{DBI}{database_name};
	my $DB_host = $Foswiki::cfg{Store}{DBI}{database_host};
	my $DB_user = $Foswiki::cfg{Store}{DBI}{database_user_ah};
	my $DB_pwd = $Foswiki::cfg{Store}{DBI}{database_password_ah};

	my $pgconnection = Pg::setdbLogin($DB_host, '5432', "", "", $DB_name, $DB_user, $DB_pwd);
	##### start PG transaction #####
	$pgconnection->exec("begin");

	my $lobjId = $pgconnection->lo_creat(Pg->PGRES_INV_WRITE);
	die "can not create large object" if $lobjId == Pg->PGRES_InvalidOid;

	my $lobj_fd = $pgconnection->lo_open($lobjId, Pg->PGRES_INV_WRITE);

	my ($keyfile,$byte_size);
	$byte_size = 0;
	while ( read( $fh, $buffer, 1024 ) ) {
		# this writes data directly into postgres big object database
		$byte_size += $pgconnection->lo_write($lobj_fd, $buffer, 1024);
		# write the stream from the user into the temp file $F
		print $F $buffer;
		# this writes the stream from the user into Memory
		$keyfile .= $buffer;		
	}



	my $FileStore = $this->getTableName('File_Store');	

	
	my $selectStatement = qq^SELECT 1 FROM $FileStore WHERE "key" = '$file_store_key' ^;
	my $insertStatement = qq^INSERT INTO $FileStore ("key", "size", file_blob) SELECT '$file_store_key', '$byte_size', '$lobjId' WHERE NOT EXISTS ($selectStatement);^;
	$pgconnection->exec($insertStatement);


	# get rid of this file to save on memory
	undef $keyfile;

	close($F)  || throw Error::Simple('DBIStoreContrib::AttachmentHandler: close ' . $fspath . ' failed: ' . $! );
	$pgconnection->exec("end");
=cut
	#### Transaction Finished for Pg ####
		
	# move the cache file to the proper location after calculating the file_store_key
	my $file_directory = $Foswiki::cfg{PubDir}.'/FileStore/'.$this->_getSubFileDirectoryByHash($file_store_key);
	$this->_doMkdirFullPath($file_directory);
	rename($fspath,$file_directory);
	chmod( $Foswiki::cfg{RCS}{filePermission}, $file_directory );
=pod
	# put in the symlink
	my $FileNameHash = sha1_hex($site_key,$ref->{web_name},$ref->{topic_name},$ref->{file_name},'');
	my $symfiledir = $Foswiki::cfg{PubDir}.'/SymLinks/'.$this->_getSubFileDirectoryByHash($FileNameHash);
	$this->_doMkdirFullPath($symfiledir);
	return undef unless eval { symlink($file_directory,$symfiledir); 1 };
=cut
	return $file_store_key;
}
sub insertFileStoreRow {
	my ($this,$file_store_key,$size) = @_;

	# Name all of the database tables
	my $site_key = $this->getSiteKey();
	my $FS = $this->getTableName('File_Store');
	
	my $insertStatement = qq/INSERT INTO $FS ("key", "size")
		VALUES (?,?) ;/; # 2 spots

	my $insertHandler = $this->database_connection()->prepare($insertStatement);

	$insertHandler->bind_param( 1, $file_store_key ); 
	$insertHandler->bind_param( 2, $size ); 

	$insertHandler->execute;

	return $file_store_key;
}
sub insertAHRow {
	my ($this,$ahrow) = @_;

	# Name all of the database tables
	my $site_key = $this->{site_key};
	my $AH = $this->getTableName('Attachment_History');
	
	my $insertStatement = qq/INSERT INTO $AH ("key", topic_key, "version", timestamp_epoch, 
			user_key, file_name, file_type, file_store_key, attachment_key, "comment", "size")
		VALUES (?,?,?,?,?,?,?,?,?,?,?) ;/; # 11 spots

	my $ah_key = $this->_createAHkey($ahrow);
	$ahrow->{key} = $ah_key;
	my $insertHandler = $this->database_connection()->prepare($insertStatement);

	$insertHandler->bind_param( 1, $ahrow->{key} ); 
	$insertHandler->bind_param( 2, $ahrow->{topic_key} ); 
	$insertHandler->bind_param( 3, $ahrow->{version});
	$insertHandler->bind_param( 4, $ahrow->{timestamp_epoch} );
	$insertHandler->bind_param( 5, $ahrow->{user_key} );
	$insertHandler->bind_param( 6, $ahrow->{file_name} );
	$insertHandler->bind_param( 7, $ahrow->{file_type} );
	$insertHandler->bind_param( 8, $ahrow->{file_store_key} );
	$insertHandler->bind_param( 9, $ahrow->{attachment_key} );
	$insertHandler->bind_param( 10, $ahrow->{comment_key},{ pg_type => DBD::Pg::PG_BYTEA });
	$insertHandler->bind_param( 11, $ahrow->{size} );
	$insertHandler->execute;

	return $ahrow->{key};
}

sub insertAttachmentRow {
	my ($this,$arow) = @_;

	# Name all of the database tables
	my $site_key = $this->{site_key};
	my $Attachments = $this->getTableName('Attachments');
  
	my $insertStatement = qq/INSERT INTO $Attachments ("key", link_to_latest, current_attachment_name, current_topic_key)
		VALUES (?,?,?,?) ;/; # 4 spots


	my $insertHandler = $this->database_connection()->prepare($insertStatement);

	$insertHandler->bind_param( 1, $arow->{key} ); 
	$insertHandler->bind_param( 2, $arow->{link_to_latest} ); 
	$insertHandler->bind_param( 3, $arow->{current_attachment_name});
	$insertHandler->bind_param( 4, $arow->{current_topic_key} );

	$insertHandler->execute;

	return $arow->{key};


}

############################################################################################
########################        Listener Call Distributor      #############################
############################################################################################

my %SourceToMetaHash = (
'readTopic'  => {  ### - Start ############   $topicObject,$topic_history_row  ##################
'FILEATTACHMENT'=> sub {
	my ($this,$topicObject,$throw) = @_;
	#  require => [qw( name )], other   => [qw( namekey version path size date user userkey comment attr )]

	my $th_key = $throw->{key};
	my $topic_key = $throw->{topic_key};
	
	my $array_ref = $this->LoadAllAttachmentsByTopicKey($topic_key);
	my $count = scalar(@$array_ref);
	
	require Foswiki::Contrib::DBIStoreContrib::ResultSetAttachment;
	my $ref = new Foswiki::Contrib::DBIStoreContrib::ResultSetAttachment($array_ref);
	my @arrayOfAttachments;
	while($ref->hasNext() ){

		my $attachment_key = $ref->currentRow('attachment_key');
		my $ahrow_key = $ref->currentRow('key');
		my $file_name = $ref->currentRow('file_name') .'.'.$ref->currentRow('file_type');
		push(@arrayOfAttachments, { name => $file_name, namekey => $attachment_key, 
				version => $ref->currentRow('version'), path => $file_name, size => $ref->currentRow('size'), 
				date => $ref->currentRow('timestamp_epoch'), 
				user => $ref->currentRow('user_key'), user_key => $ref->currentRow('user_key'),
				comment => $ref->currentRow('comment'), ext => $ref->currentRow('file_type')	} );

	}
	$topicObject->putAll('FILEATTACHMENT',@arrayOfAttachments);
	return 1; 
}
}  #### readTopic - Finished
);

sub listener {
	my $site_handler = shift;

	my $sourcefunc = shift;
	my @vars = @_;
	# will need this after calling listeners in order to set the site_handler back to what it was before
	my $currentClass = ref($site_handler);
	# need to initialize the object
	my $this = Foswiki::Contrib::DBIStoreContrib::AttachmentHandler->init($site_handler);

	# these are pieces of the Meta topicObject		
	my @MetaHashObjects = ('FILEATTACHMENT');
	my $sourcFuncRef = $SourceToMetaHash{$sourcefunc};

	foreach my $MetaHash (@MetaHashObjects) {
		$SourceToMetaHash{$sourcefunc}{$MetaHash}->($this,@vars) if exists($SourceToMetaHash{$sourcefunc}{$MetaHash});
	}
	# return handler to previous state
	bless $this, $currentClass;
	

}

############################################################################################
########################  		      Miscellaneous		      #############################
############################################################################################
sub _getSubFileDirectoryByHash {
	my ($this,$file_key) = @_;
	
	my $prima_dir = substr($file_key,-4,1);
	my $segunda_dir = substr($file_key,-3);
	my $file_directory = $prima_dir.'/'.$segunda_dir.'/'.$file_key;
	my ($untainted_fd) = $file_directory =~ m/^(.*)$/; # have to untaint
	return $untainted_fd;
}

sub _doMkdirFullPath {
	my ($this,$fulldir) = @_;
	my ($file_name,$path,$file_type) = File::Basename::fileparse($fulldir,qr/\.[^.]*/);
	my $bool = make_path( $path );
	warn "Make Path: $bool\n";
}

sub _createAHkey {
	my ($this,$ahrow) = @_;
	# key = sha1( 1-file_name, 2-file_type, 3-size, 4-timestamp_epoch, 5-file_store_key, 6-user_key, 7-topic_key, 8-attachment_key)	
	my $ah_key = substr(sha1_hex($ahrow->{file_name},$ahrow->{file_type},$ahrow->{size},$ahrow->{timestamp_epoch},
			$ahrow->{file_store_key},$ahrow->{user_key},$ahrow->{topic_key},$ahrow->{attachment_key} ), 0, - 8);

	return $ah_key;
	
}

1;
__END__

