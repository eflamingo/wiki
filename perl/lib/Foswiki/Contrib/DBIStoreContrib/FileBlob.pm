#!/usr/bin/perl -w -T

package Foswiki::Contrib::DBIStoreContrib::FileBlob;


use strict;
use warnings;

use Data::Dumper();
use Crypt::PBC;
use Crypt::CBC;
use Digest::SHA qw(hmac_sha256_hex hmac_sha256 sha256_hex sha256);
use Digest::SHA1 qw(sha1);
use MIME::Base64 qw(decode_base64 encode_base64);
use MIME::Base16;
use Encode::Base58;
use IO::Socket::UNIX qw( SOCK_STREAM );
use JSON ();
use Cwd;

# internal variables
my $BLOBTYPES = {
	'original' => 1,
	'pdf' => 1,
	'txt' => 1,
	'html' => 1,
	'picture_small_png' => 1,
	'picture_medium_png' => 1,
	'picture_large_png' => 1,
	'Blob_Store' => 1
};

my @SKIPDIRECTORIES = (
	'upload',
	'cipher',
	'Blob_Store',
	'Blob_Store.tar.gz',
	'info'
);

=pod
---+ Internal Functions
The following functions are for use inside this function.

=cut


=pod
---++ _moveIntoCache()
Moves a temporary file into Cache.  There is no double checking of whether the file is already in cache or just in the 
...temporary directory.  Be careful.

Also, this is the function that creates the "info" file.
=cut
sub _moveIntoCache {
	my $this = shift;

	my $fdir = $this->{'file_directory'};
	my $fpFrom = $this->{'file_path'};
	
	# file info should have already been loaded by now
	my $sha = $this->{'sha256sum'};

	# derive the final directory
	# ...this command also creates the necessary directories
	my $fpTo = $this->_deriveDirectory();

	# move the file using bash commands
	my $output = `mv $fpFrom $fpTo/original`;

	# after file has moved, reset file_path to new location
	# ..now this is a directory, not a file
	$this->{'file_path'} = $fpTo;

	# write file info ../info
	# ...in this format: 1-shk,2-whkey,3-topic_key,4-file_type,5-sha256sum
	my ($fname,$ftype) = ($this->{'file_name'},$this->{'file_type'});
	my ($s1,$w1,$t1) = ($this->ID->[0],$this->ID->[1],$this->ID->[2]);
	my $topichistorykey = $this->key;
	$output = `rm $fpTo/info`;
	$output = `echo "$s1" > $fpTo/info`;
	$output = `echo "$w1" >> $fpTo/info`;
	$output = `echo "$t1" >> $fpTo/info`;
	$output = `echo "$topichistorykey" >> $fpTo/info`;
	$output = `echo "$ftype" >> $fpTo/info`;
	$output = `echo "$sha" >> $fpTo/info`;


	return 1;
}



sub key {
	my $this = shift;
	return $this->{'key'} if defined $this->{'key'};
	return $this->_deriveKey();
}

=pod
---++ _fileInfoLoad()
Loads all of the relevant information from a file:
   * sha256sum
   * size
=cut

sub _fileInfoLoad {
	my $this = shift;
	# check if there is a file_path
	if(-d $this->{'file_path'}){
		# file_path points to a directory, so we need to get at ../original
		my $fptmp = $this->{'file_path'}.'/original';
		my $fdir = $this->{'file_directory'};

		# find the size of this file
		my $tmp = "";
		$tmp = `du -b $fptmp` if -f $fptmp;
		if($tmp =~ m/^([0-1]+)/){
			$this->{'size'} = $1;
		}
		# find the sha256 hash of the file blob
		$tmp = "";
		$tmp = `sha256sum $fptmp` if -f $fptmp;
		if($tmp =~ m/^([a-z0-9]+)/){
			$this->{'sha256sum'} = $1;
		}
		
		# scoop up the ../info text file
		$this->_scoopInfoFile();

	}
	elsif(-f $this->{'file_path'}){
		# file_path points to a file (a temporary file in tmp)
		my $fptmp = $this->{'file_path'};
		my $fdir = $this->{'file_directory'};

		# find the size of this file
		my $tmp = `du -b $fptmp`;
		if($tmp =~ m/^([0-1]+)/){
			$this->{'size'} = $1;
		}
		# find the sha256 hash of the file blob
		$tmp = `sha256sum $fptmp`;
		if($tmp =~ m/^([a-z0-9]+)/){
			$this->{'sha256sum'} = $1;
		}
		# derive the key for the file blob
		$this->_deriveKey();
	
	}
	else{
		# file does not exist, not good
		return undef;
	}
	
	return 1;
}
=pod
---++ _scoopInfoFile()->1 for success (ie info file exists) or 0 for fail
Scoops up the ./info text file and inputs the information into the FileBlob object.
=cut
sub _scoopInfoFile {
	my $this = shift;

	my $infoFP = $this->{'file_path'}.'/info';
	return undef unless -f $infoFP;

	my $info = `cat $infoFP`;
	# go line by line, get the ID, sha256sum if it hasn't already been scooped,
	# ...1-shk,2-whkey,3-topic_key,4-file_type,5-sha256sum
	my @id;
	my $counter = 1;
	foreach my $infoline (split("\n",$info)){
		$id[0] = $infoline if $counter == 1;
		$id[1] = $infoline if $counter == 2;
		$id[2] = $infoline if $counter == 3;
		$this->{'key'} = $infoline if $counter == 4;
		$this->{'file_type'} = $infoline if $counter == 5;
		$this->{'sha256sum'} = $infoline if $counter == 6;
		$counter++;
	}
	$this->ID(\@id);
	return 1;
}

=pod
---++ _deriveDirectory()-> full path to cache destination
In order to avoid overcrowding in directories, make daf392dff -> d/af3/92dff 
=cut
sub _deriveDirectory {
	my $this = shift;
	my $fdir = $this->{'file_directory'};
	my $filepath = $this->{'file_path'};
	my $sha = $this->_deriveKey();

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
	
	my $output = `mkdir -p $fdir/$nested`;
	# create directories for all blob types
	foreach my $btype (keys %{$BLOBTYPES}){
		$output = `mkdir -p $fdir/$nested/upload/$btype`;
	}
	return $fdir.'/'.$nested;
}
# same as above.... $this->_deriveFilePath($sha)->file_path
sub _deriveFilePath {
	my $this = shift;
	my $sha = shift;
	my @array = split('',$sha);
	my $nested = "";
	my $counter = 0;
	foreach my $char (@array){
		$nested .= $char;
		$nested .= '/' if $counter == 1; # / after the first character
		$nested .= '/' if $counter == 4; # / after the fourth character
		$counter++;
	}
	return $this->{'file_directory'}.'/'.$nested;
}


=pod
---++ filehande($direction,$type,$blobtype)
This returns a scalar which can be used as a filehandle.  Please remember to close the filehandle when you are done.
   * $direction -> either '<' for read???? or '>' for write????
   * $type -> 'cipher' or 'clear'
   * $blobtype -> ''
=cut
sub filehandle {
	my $this = shift;
	my ($direction,$clearOrcipher,$blobtype) = (shift,shift,shift);
	my $pieceNum = shift;

	if( $direction ne '<' && $direction ne '>' ){
		# check if the direction arguement makes sense.
		return undef;
	}
	if($clearOrcipher !~ m/(clear|cipher)/){
		# check if the direction arguement makes sense.
		return undef;
	}
	# check if the BLOB type is valid
	return undef unless $BLOBTYPES->{$blobtype};


	my $filehandle;
	my $handlepath = $this->{'file_path'};
	if($pieceNum =~ m/([0-9]+)/){
		# we need to grab a piece of a file (probably for encryption or decryption)
		$handlepath .= '/upload/'.$blobtype.'/'.$1;
		# append cipher subscript
		$handlepath .= '.cipher' if $clearOrcipher eq 'cipher';
	}
	else{
		$handlepath .= '/'.$blobtype;
	}
	open($filehandle,$direction,$handlepath);
	return $filehandle;
}


=pod
---+ External Functions
The following functions are available to external programs and modules.
=cut


=pod
---++ new({key => $key}) or new({ 'shk' => $shk, 'whk' => $whk, 'topic_key' => $topic_key })
Creates a file blob object.  Every blob starts off empty unless the key is given.
   * Option A: feed in a file_blob_key (hmac_sha256), then either call load() or download() from the mothership
   * Option B: feed in an @ID, then call load(...file path...) which will automatically figure out the _deriveKey() 
=cut
sub new {
	my($class, $args) = @_;

	my $this = bless({}, $class);



	# TODO: use LocalSite.cfg file to set this variable
	$this->{'file_directory'} = $Foswiki::cfg{WorkingDir}.'/fileblob';#'/var/lib/kgc/lib/fileblob';
	$this->{'BufferSize'} = 8192;
	$this->{'split_size'} = '1000K'; # 100K = 100*1024 
	$this->{'kgc_socket_path'} = '/var/run/kgc/kgc-server.socket';


	# if there are no args, return an empty object
	return $this unless defined $args;


	$this->{'topic_revision_info'} = $args->{'topic_revision_info'};
	my $throw = $this->{'topic_revision_info'};

	# Temporary Bulk Loading Measure
	# ...add session ID to $throw
	my $wezifingerprint = $Foswiki::cfg{weziFingerPrint};
	my $weziMail =  $Foswiki::cfg{weziMail};
	# doing bulk upload, so use special bulk gpg key for signature
	# from 2009/1/1 till 2013/07/18
	# order matters here! TIME->USERID->WEZI
	$throw->{'SessionInfo'} = [qq{TIME:FROM[1230768001]TO[1374116309]},qq{USERID:[ALL]},
			qq{WEZI:MAIL[$weziMail]FINGERPRINT[$wezifingerprint]}];

	my $topickey = $throw->{'Topic_History'}->[0];

	
	my $thkey = 0; #<-- must be derived from Topic_History row


	# file_path -> file_directory.'/'.deriveKey($topic_key).'/'.randomNumber (probably time())
	my $relativeFP = $this->_deriveRelativePath($topickey).'/'.time();

	$this->{'file_path'} = $this->{'file_directory'}.'/'.$relativeFP;

	# define the @id;
	my @id;
	if(ref($args->{'ID'}) eq 'ARRAY'){
		@id = @{$args->{'ID'}};
		die "ID is not properly formated." if scalar(@id) < 3;
		
		$this->ID(\@id);
	}
	else{
		die "No ID";
	}

	# write 'topic_revision_info' to disk
	# ..the key will also be calculated here
	$this->_parseTopicRevision();

	# create the info file (for quick scooping later)
	open(my $fh1,'>',$this->{'file_path'}.'/info') || die "can't create info file";
	print $fh1 $this->ID->[0]."\n"; # <--$site_history_key
	print $fh1 $this->ID->[1]."\n"; # <--$web_history_key
	print $fh1 $this->ID->[2]."\n"; # <--$topic_key
	print $fh1 $this->key."\n";
	close $fh1;


	# write file to disk (from passed filehandle)

	return $this;
}

=pod
---++ _parseTopicRevision
This function is called by "new".
   1. TODO:Check that the topic history hash is complete...
   1. TODO:Check that the Blob_Store keys are valid
   1. Write the topic history information to disk
=cut
sub _parseTopicRevision {
	my $this = shift;
	my $throw = $this->{'topic_revision_info'};
	my $thtopickey = $throw->{'Topic_History'}->[0];
	my $thkey = 0; # <-- derive this somewhere?

	
	# file_path is set to a random location, because we can't calculate the sha256sum hash yet	
	my $wkdir = $this->{'file_path'};

	# delete everything if the file_path is already occupied
	if(-d $wkdir){
		`rm -r $wkdir`;
	}
	`mkdir -p $wkdir`;

	my $x = 0; # <-- for deriving unique file names
	foreach my $tablename (sort keys %{$throw}){
		$x++;
		my $tabletmp = "";

		foreach my $brow (@{$throw->{$tablename}}){
			$x++;
			next unless defined $brow;
			my $tmp = "";
			if(ref($brow) eq 'ARRAY'){
				# for MULTIPLE, rows are referenced
				foreach my $bcell (@{$brow}){
					$x++;
					# change UUID format to base58
					# TODO: do we really need to do this?
					#if($bcell =~ m/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/){
					#	my $bcellUUID = $1;
					#	$bcellUUID =~ s/\-//g;
					#	$bcellUUID = MIME::Base16::decode($bcellUUID);
					#}
					$tmp .= "$bcell\n" if defined $bcell;
					$tmp .= "\n" unless defined $bcell;
				}
				next if $tmp =~ m/^[\r\n\s]+$/ || $tmp eq '';

				# create a temporary file
				my $tmpfilenameCell = $wkdir.'/'.time().$x;

				open (my $myfile, ">", "$tmpfilenameCell") or die "can't open file!"; 
				print $myfile $tmp;
				close $myfile;

				my $newfilenameCell;

				# move the tmp file to it's new location
				if($tablename eq 'Blob_Store'){
					$newfilenameCell = $this->blobhash($brow->[1],$thtopickey);
					# convert to hexadecimal string
					$newfilenameCell =  $this->_encodeBase58($newfilenameCell);
					# Blob_Store is not included in the deriveKey calculation, so
					# ...it goes in its own directory
					mkdir $wkdir.'/'.$tablename unless -d  $wkdir.'/'.$tablename ;
					my $new002002 = $wkdir.'/'.$tablename.'/'.$newfilenameCell;
					`mv $tmpfilenameCell $new002002`;

				}
				else{
					# do a double sha256
					$newfilenameCell = $this->dhash(undef,$tmpfilenameCell);
					# convert to hexadecimal string
					$newfilenameCell = $this->_encodeBase58($newfilenameCell);
					my $new002002 = $wkdir.'/'.$tablename.'.'.$newfilenameCell;
					`mv $tmpfilenameCell $new002002`;
				}

			}
			else{
				$x++;
				next if $brow =~ m/^[\r\n\s]+$/ || $brow eq '' || !(defined $brow);
				# for SINGLE, goes directly to a row
				my $tmpfilenameCell = $wkdir.'/'.$tablename;
				open (my $NOFILE, ">>", "$tmpfilenameCell") or die "can't open file!"; 
				print $NOFILE "$brow\n";
				close $NOFILE;

				$tabletmp .= "   $brow\n";

			}
		}
		next if $tabletmp =~ m/^[\r\n\s]+$/;
		next unless defined $tabletmp && $tabletmp ne '';
	}


	# calculate the fileblobkey
	$this->_deriveKey;

	my $key = $this->key;

	# derive the new directory
	my $newfilepath = $this->{'file_directory'}.'/'.$this->_deriveRelativePath($thtopickey).'/'.$this->_deriveRelativePath($key);

	my $oldfilepath = $this->{'file_path'};


	# move the file
	if(-d $newfilepath){
		`rm -r $newfilepath`;
		`mkdir -p $newfilepath`;
	}
	else{
		`mkdir -p $newfilepath`;
	}
	`mv  $oldfilepath/* $newfilepath/`;
	`rm -r $oldfilepath`;
	die "could not move temporary directory" unless -d $newfilepath;
	$this->{'file_path'} = $newfilepath;
=pod
	# create a Blob_Store.tar.gz for uploading later
	if(-d $this->{'file_path'}.'/Blob_Store'){
		# ... Compress tar -czpf /tmp/mother.tar.gz Blob_Store
		# ... Decompress: tar -xvzf /tmp/mother.tar.gz -C /targetdir
		my $dir = $this->{'file_path'};
		$dir =~ /^(.*)$/ && ($dir = $1);
		my $pwd = cwd(); #<--- we need to change directories
		$pwd =~ /^(.*)$/ && ($pwd = $1);
		chdir($dir);
		`tar -czpf Blob_Store.tar.gz Blob_Store`; # <-- now we can tar up only relative filepaths
		chdir($pwd); #<--- go back to the original directory perl was in
	}
=cut

	#my $testoutput = `du -sh $newfilepath`;

	#die "New Path:$testoutput";

}
=pod
---++ _deriveKey()
This is used by _parseTopicRevision to calculate the sha256sum hash of the revision. (the fileblobkey).
=cut
sub _deriveKey {
	my $this = shift;

	return undef unless $this->ID;
	# TODO: check if ID has 3 elements
	my @ID = @{$this->ID};
#	require Data::Dumper;
#	my $x001 = Data::Dumper::Dumper(@ID);
#	die "MOFO:$x001\n";

	# load up everything in the file_path
	my $wkdir = $this->{'file_path'};
	die "no working directory." unless -d $wkdir;
#  find /var/www/wiki/core/working/fileblob/36/dcf/eb359a34b1f847b175f2d8240d1/00/4a6/2726838ca651b408bb5d8930ba8 -name '*'  -type f -exec sha256sum {} 2>/dev/null \\; |
# find /var/www/wiki/core/working/fileblob -name '*'  -type f -exec sha256sum {} 2>/dev/null \\; 
	my $output = "";
	my $basedir = $this->{'file_path'};
	open(my $fh, " find $wkdir -name '*'  -type f -exec sha256sum {} 2>/dev/null \\;  | sort -n -k2 | cut -f 1 
|") || die "error doing fileblobkey calculation";
	while(my $row = <$fh>){
		my $skipme = 0;
		foreach my $baddirectory (@SKIPDIRECTORIES){
			# Blob_Store and upload must be excluded from the deriveKey calculation
			$skipme = 1 if $row =~ m/$baddirectory/;
		}
		next if $skipme == 1;

		# change hexadecimal to base58
		#if($row =~ m/^([0-9a-z]+)/){
		#	my $orig = $1;
		#	my $hexa = MIME::Base16::decode($1);
		#	$hexa = $this->_encodeBase58($hexa);
		#	$row =~ s/$orig/$hexa/g;
		#}

		# strip out the relative directories
		# also strip the trailing slash
		$row =~ s/$basedir\///g;

		$output .= $row;
	}
	close $fh;

	$this->{'sha256sum'} = $output;
	# add a checksum
	my $key = $this->_encodeBase58($this->fhash($output));
	#my $checksum = substr();
	$this->{'key'} = $key;

	return $this->{'key'};
}

# ($topickey)-> relative file path
sub _deriveRelativePath {
	my $this = shift;
	my $sha = shift;
	die "no key" unless defined $sha;

	# make sure that there are no hyphens
	$sha =~ s/\-//g;
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

=pod
---++ Hashes
Hashing files, blob_store values, fileblob.

Put everything into binary! No hex!
=cut

=pod
---+++ fhash($file)
Used to hash the output file from deriveKey function

=cut
sub fhash {
	my $this = shift;
	my $output = shift;
	
	return sha256(sha256($output));
}


=pod
---+++ dhash($file,$filepath)->sha256(sha256(sum))
Used to hash metadata files.
http://crypto.stackexchange.com/questions/779/hashing-or-encrypting-twice-to-increase-security

"hello"
2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824 (first round of sha-256)
9595c9df90075148eb06860365df33584b75bff782a510c6cd4883a419833d50 (second round of sha-256)
Everything is in binary.
=cut
sub dhash {
	my $this = shift;
	my $file = shift;
	my $filepath = shift;
	if(defined $file){
		return sha256(sha256($file));
	}
	elsif(defined $filepath){
		die "no file or file path" unless -f $filepath;
		my $newfilenameCell = `sha256sum $filepath`;
		if($newfilenameCell =~ m/^([a-z0-9]+)/){
			# convert hex to binary;
			return sha256(MIME::Base16::decode($1));
		}
		else{
			die "something wrong with sha256sum.";
		}
	}
	else{
		die "no good inputs for dhash().";
	}


}

=pod
---+++ blobhash($blob.value)->hmac_sha256($blob,$topickey)
=cut
sub blobhash {
	my $this = shift;
	my $data = shift;
	my $topickey = shift;
	
	# strip the hyphens from the UUID ($topickey)
	$topickey =~ s/\-//g;
	# convert the UUID to binary
	$topickey = MIME::Base16::decode($topickey);
	
	return hmac_sha256($data,$topickey);
}

=pod
---+++ encodeBase58($binarydata)->base58
This is needed for blobhash, fhash,dhash.

The input comes from sha256 (usually).
=cut
sub _encodeBase58 {
	my $this = shift;
	my $data = shift;
	die "no Number for encodeBase58" unless defined $data;
	use bignum;
	return Encode::Base58::encode_base58(hex (MIME::Base16::encode( $data)));
}


=pod
---++ load({file_path => $filepath, file_handle => $fh })
A file is required.  The file can either be inside a scalar, or on disk somewhere referenced by a file_path.  The file_path is given priority over scalar in case both are given.

=cut
sub load {
	my $this = shift;
	my $args = shift;
	# these items should be in the arguments	
	$this->{'file_name'} = $args->{'file_name'};
	$this->{'file_type'} = $args->{'file_type'};
	

	my $tempfilename = time();
	my $fdir = $this->{'file_directory'};

	# upload the file into the tmp folder
	# ... use -f tag to insure file_path points to a file, not a directory
	if(-f $args->{'file_path'}){
		# load the file into a temporary location using bash commands
		my $origfilepath = $args->{'file_path'};
		my $to = $fdir.'/tmp/'.$tempfilename;
		my $output = `cp $origfilepath $to`;

		# set the internal filepath to the temporary location of the file (this is the file, not the directory)
		$this->{'file_path'} = $to;
	}
	elsif($args->{'file_handle'}){
		# create a file handle to a temporary location
		my $to = $fdir.'/tmp/'.$tempfilename;
		$this->{'file_path'} = $to;
		my $TEMPORARYFILE;
		open($TEMPORARYFILE,'>',$to) || die "can't create temporary file.\n";

		# there is a file handle, read in the file
		my $TARGETFILE = $args->{'file_handle'};
		# ...this filehandle has already been opened.

		my $donesize = 0;
		my $line;
		binmode($TEMPORARYFILE);
		binmode($TARGETFILE);
		while(read($TARGETFILE,$line,$this->{'BufferSize'}) !=0){
			$donesize += $this->{'BufferSize'};
			# write line into temporary file
			print $TEMPORARYFILE $line;
			
		}
		# close both file handles, since we are done reading and writing data
		close $TARGETFILE;
		close $TEMPORARYFILE;
	}
	else{
		# there is nothing to do
		return undef;
	}

	# derive the file information
	$this->_fileInfoLoad();

	# move the file to the cache directory
	$this->_moveIntoCache();
	
	return $this;
}


=pod
---++ encrypt()-> 0 for fail, 1 for success
This takes the clear text of the file and encrypts it via the kgc (Unix Domain Socket)
   1. Compress the file
   1. Sign the file with the Ardhi/Wezi's GPG key
   1. Encrypt the file via the KGC
=cut

sub encrypt {
	my $this = shift;
	my $test = 0;
	# loop through all of the blob types
	foreach my $blobtype (keys %{$BLOBTYPES}){
		my $clearFP = $this->{'file_path'}.'/'.$blobtype;
		# 
		# create a Blob_Store.tar.gz for uploading later
		if($blobtype eq 'Blob_Store' && -d $this->{'file_path'}.'/'.$blobtype){
			# ... Compress tar -czpf /tmp/mother.tar.gz Blob_Store
			# ... Decompress: tar -xvzf /tmp/mother.tar.gz -C /targetdir
			my $dir = $this->{'file_path'};
			$dir =~ /^(.*)$/ && ($dir = $1);
			my $pwd = cwd(); #<--- we need to change directories
			$pwd =~ /^(.*)$/ && ($pwd = $1);
			chdir($dir);
			`tar -czpf Blob_Store.tar.gz Blob_Store`; # <-- now we can tar up only relative filepaths
			chdir($pwd); #<--- go back to the original directory perl was in
		}
		else{
			# skip if the blob type does not exist
			next unless -f $clearFP;
		}

		$test = 1;
	
		# compress the file, .gz is now appended to clearFP .................#
		my $clearFPgz = $clearFP.'.gz';
		if($blobtype eq 'Blob_Store'){
			# then the file has already been compressed and tar
			$clearFPgz = $clearFP.'.tar.gz';
		}
		else{
			`cat $clearFP | gzip -f > $clearFPgz`;
		}

		# use the output to get file_paths to all

		my $input;
		# get the file size
		my $tmpsize = `du -b $clearFPgz`;
		if($tmpsize =~ m/([0-9]+)/){
			$input->{'file_size'} = $1;
		}
		# append .cipher to blob name
		my $fpToCipherPiece = $this->{'file_path'}.'/cipher/'.$blobtype;
		unless(-d $this->{'file_path'}.'/cipher/'){
			# create the cipher directory
			my $tttotott = $this->{'file_path'}.'/cipher';
			`mkdir -p $tttotott`;
		}
		# encrypt each file via KGC .........................................#
		my ($clearFH,$cipherFH);

		$input->{'clear_file_path'} = $clearFPgz;
		$input->{'cipher_file_path'} = $fpToCipherPiece;
		my $answer = "";
		my $DontGiveUp = 1;
		my $counter = 0;
		while($DontGiveUp && $counter < 30){
			eval{
				$counter++;
				$answer = $this->_individualEncrypt($input);
				$DontGiveUp = 0;
				
				if( $blobtype eq 'Blob_Store'){
					# get rid of the tar.gz file
					`rm -r $clearFPgz`;
				}
			};
			if($@){
				# there was a problem, try again
				warn $@."\n";
				# the following tells the program to sleep for .5 seconds
				select(undef, undef, undef, 0.5);
			}
		}
		die "Fetch failed" if $counter >= 30;
#die "what's up?\n$clearFPgz\n$fpToCipherPiece" if $blobtype eq 'Blob_Store';
		# get the crypto information, put it in the upload directory
		my $jsontext = $answer->{'json text'};
		my $clearFPjson = $this->{'file_path'}.'/upload/'.$blobtype.'.json';

		# check if upload folder exists
		if(-d $this->{'file_path'}.'/upload'){
			# do nothing
		}
		else{
			my $tmp00122 = $this->{'file_path'}.'/upload';
			`mkdir -p $tmp00122`;
		}

		# Author hated dealing with files, so we use the command line instead
		open(my $jsonFH,'>',$clearFPjson) || die "File won't open.\n";
		print $jsonFH $jsontext;
		close $jsonFH;
	}
	# split the file up first
	my @splits = @{$this->_split()};
	return 1;
}
=pod
---++ ID(\($site_history_key,$web_history_key,$topic_key))->\@ID used in HIBE
This allows UUIDs to be put into a file blob for use in the HIBE encryption/decryption.

=cut
sub ID {
	my $this = shift;
	my $inputIDref = shift;

	if(ref($inputIDref) eq 'ARRAY' && scalar(@{$inputIDref}) == 3){
		my @base58ID;
		foreach my $id (@{$inputIDref}) {
			# change each id from UUID
			# ...strip hyphens
			$id =~ s/\-//g;
			$id = $this->_encodeBase58(MIME::Base16::decode($id));
			push(@base58ID,$id);
		}
		$this->{'ID'} = \@base58ID;
	}
	return $this->{'ID'};
}

=pod
---++ _individualEncrypt($file_path_to_piece)
Encrypts individual files.  This function is not so smart, since it took so much effort to get it working in the first place.  Therefore, the input argument needs a lot of information:
   * file_size (in bytes, equivalent to perl's length() function)
   * clear_file_path -> a path the file that will be sent to the KGC
   * clear_file_handle -> file handle to clear text file (file should already exist)
   * cipher_file_handle -> file handle to future cipher text 

Required permissions are:
kgc-user@example.com:/var/run/kgc$ ls -la
total 0
drwxr-xr-x  2 kgc-user kgc-user  60 2013-07-03 16:16 .
drwxr-xr-x 26 root     root     980 2013-07-03 16:18 ..
srwxrwxr-x  1 kgc-user kgc-user   0 2013-07-03 16:16 kgc-server.socket

=cut

sub _individualEncrypt {
	my ($this,$input) = (shift,shift);
	# make sure that there is a real clear text file on disk to be encrypted
	return undef unless -f $input->{'clear_file_path'};


	my $fhmsg;
	my $fhcpr;

	open($fhmsg,'<', $input->{'clear_file_path'}) || die "File won't open.\n";
	open($fhcpr,'>',$input->{'cipher_file_path'}) || die "File won't open.\n";

	binmode($fhmsg);
	binmode($fhcpr);

	my $startblob = "---STARTBLOB---";
	my $endblob = "---ENDBLOB---";
	$input->{'STARTBLOB'} = 0;
	$input->{'ENDBLOB'} = 0;

	my $socket = IO::Socket::UNIX->new(
   Type => SOCK_STREAM,
   Peer => $this->{'kgc_socket_path'},
)
   or die("Can't connect to server: $!\n");


	my $answer;
	$answer->{'STARTBLOB'} = 0;
	$answer->{'ENDBLOB'} = 0;

	my ($s1,$w1,$t1) = ($this->ID->[0],$this->ID->[1],$this->ID->[2]);
	return undef unless $s1 && $w1 && $t1;
	
	my $requestString = qq/type=MENCRYPT
ID=[$s1;$w1;$t1]/;
	my @msglines = split("\n",$requestString);

	my $donesize = 0;
	my $BufferSize = $this->{'BufferSize'};
	my $totalsize = $input->{'file_size'};
	
	# send the first line of the message
	my $linecount = 0;
	my $NumOfLines = scalar(@msglines);
	print $socket $msglines[$linecount]."\n";
	$linecount++;
	# initiate this to 1 to indicate that we need to start reading the clear_file
	$input->{'last_read_length'} = 1;

	# this is for when the kgc still has to talk, but the client has finished
	while( my $line = <$socket> ){
		chomp($line);
		$line =~ s/SESSIONNEWLINERN/\r\n/g;
		$line =~ s/SESSIONNEWLINEN/\n/g;

		#print "Received Message:$line\n";
		my $response;
		# ................send in the message text to the kgc..................
		if($linecount < $NumOfLines){
			# start sending the header information
			$response = $msglines[$linecount];
			$linecount++;
		}
		elsif($linecount >= $NumOfLines && $input->{'STARTBLOB'} != 1){
			# send the star blob message
			$response = $startblob;
			$input->{'STARTBLOB'} = 1;
		}
		elsif($linecount >= $NumOfLines && $input->{'STARTBLOB'} == 1 && $input->{'ENDBLOB'} != 1 && read($fhmsg,$response,$BufferSize) != 0){
			# we are in the middle of a binary run
			#my $rc = read($fhmsg, $response, $BufferSize, $donesize);
			#$response = encode_base64($response);
			
			$donesize += $BufferSize;
		}
		elsif( $input->{'ENDBLOB'} != 1){
			# it is implied by the ordering of the elsif that there is no more data to read
			# we finished sending the cipher text, send endblob to kgc
			$response = $endblob;
			$input->{'ENDBLOB'} = 1;
		}
		elsif($input->{'ENDBLOB'} == 1){
			# we are waiting for clear text from the kgc
			$response = "more";

		}

		# ................read in the $line from the kgc..................
		# put JSON reader here
		if($line =~ m/^JSON=(.*)/){
			$answer->{'json text'} = $1;
			# get rid of newlines
			$answer->{'json text'} =~ s/MENCRYPTNEWLINE/\n/g;
			$answer->{'json'} = JSON::from_json($answer->{'json text'},{utf8 => 1});
		}
		elsif($line =~ m/^---STARTBLOB---$/){
			$answer->{'STARTBLOB'} = 1;

		}
#....................................................................................>>>>>
		elsif($answer->{'STARTBLOB'} == 1 && $line !~ m/^---ENDBLOB---$/ && $answer->{'ENDBLOB'} != 1 ){
			# we are in the middle of a message
			# scoop the cipher text
			my $templine = $line;
			#$templine =~ s/MENCRYPTNEWLINE/\n/g;
			#$templine = decode_base64($templine);
			

			#$answer->{'cipher text'} .= $templine;
			print $fhcpr $templine;
		}
#....................................................................................>>>>>
		elsif($line =~ m/^---ENDBLOB---$/){
			$answer->{'ENDBLOB'} = 1;
		}
		elsif($line eq "KGC Finished"){
			# KGC has indicated that the connection is over.
			last;	
		}		
		#print "postdom($line)($response)\n";
		$response =~ s/\r\n/SESSIONNEWLINERN/g;
		$response =~ s/\n/SESSIONNEWLINEN/g;
		print $socket "$response\n";
	}
	close $fhmsg;
	close $fhcpr;
	return $answer;
}

=pod
---++ split()->\@array of blobtypes that were split 
Only cipher texts are split, and only before being uploaded to a mothership.

This function is used almost exclusively with encrypt()
=cut

sub _split {
	my $this = shift;
	my @splits;

	# for each blob type, encrypt
	foreach my $blobtype (keys %{$BLOBTYPES}){
		my $target = $this->{'file_path'}.'/cipher/'.$blobtype;

		# skip if the file does not exist		
		next unless -f $target;
		my $splitsize = $this->{'split_size'};
		
		# check if directory exists
		unless(-d  $this->{'file_path'}.'/upload/'.$blobtype){
			# create a new directory
			my $xyz =  $this->{'file_path'}.'/upload/'.$blobtype;
			`mkdir -p $xyz`;
		}
		my $prefix = $this->{'file_path'}.'/upload/'.$blobtype.'/cipher_';
		# use a bash command to split the file into 1 MB pieces
		my $output;
		$output = `rm -f $prefix*`; # <-- just in case, delete existing files
		$output = `split -b $splitsize $target $prefix`;# <-- split files
		push(@splits,$blobtype);
	}
	return \@splits;
}

=pod
---++ decrypt()-> 1 for success, 0 for failure
This takes the cipher text of the file and decrypts it via the kgc.
   1. Scoop up json text (needed by the HIBE)
   2. Merge all of the pieces for each blob type into a single cipher file
   3. Send each cipher file to the kgc
=cut

sub decrypt {
	my $this = shift;
	my $test = 0;
	# scoop up ../info (shkey,whkey,topic_key)
	return undef unless $this->_scoopInfoFile();

	# loop through all of the blob types
	foreach my $blobtype (keys %{$BLOBTYPES}){
		my $clearFP = $this->{'file_path'}.'/'.$blobtype;
		my $cipherFP = $clearFP.'.cipher';

		# get the json text first...........................................#
		my $cipherJsonFP = $clearFP.'.json';
		next unless -f $cipherJsonFP;
		
		my $jsontext = `cat $cipherJsonFP`;

		# skip if the blob type does not exist
		next unless -f $cipherFP;
		
		# put the cipher text into the kgc .................................#
		
		# append .gz to blob name, since this file was compressed before encrypting
		my $clearFPgz = $clearFP.'.gz';

		# encrypt each file via KGC .........................................#
		my ($clearFH,$cipherFH);
		my $input;
		$input->{'json text'} = $jsontext; # <-- be careful, NOT 'json_text', but 'json text'
		$input->{'clear_file_path'} = $clearFPgz;
		$input->{'cipher_file_path'} = $cipherFP;
		my $answer = "";
		my $DontGiveUp = 1;
		my $counter = 0;
		while($DontGiveUp && $counter < 30){
			eval{
				$counter++;
				$answer = $answer = $this->_individualDecrypt($input);
				$DontGiveUp = 0;				
			};
			if($@){
				# there was a problem, try again
				warn $@."\n";
				select(undef, undef, undef, 0.5);
			}
		}
		die "Fetch failed" if $counter >= 30;
		# gunzip (decompress gz file)
		my $gunoutput = `gunzip -f $clearFPgz -c > $clearFP` if -f $clearFPgz;
		
	}
	# split the file up first
	#my @splits = @{$this->_split()};
	return 1;
}

=pod
---++ _individualDecrypt($input)

=cut
sub _individualDecrypt {
	my $this = shift;
	my $input = shift;

	my $socket = IO::Socket::UNIX->new(
   Type => SOCK_STREAM,
   Peer => $this->{'kgc_socket_path'},
)
   or die("Can't connect to server: $!\n");

	# pull in the jsontext which is full of annoying new lines
	my $jsontext = $input->{'json text'};
	# strip new lines, so that we can feed in the json text as a single line
	$jsontext =~ s/\n/MENCRYPTNEWLINE/g;

	my $fhmsg;
	my $fhcpr;
	# writing to fhmsg and reading from fhcpr
	open($fhmsg,'>', $input->{'clear_file_path'}) || die "File won't open.\n";
	open($fhcpr,'<',$input->{'cipher_file_path'}) || die "File won't open.\n";

	binmode($fhmsg);
	binmode($fhcpr);


	print "decrypting\n";
	# pick a buffer size
	my $BufferSize = $this->{'BufferSize'};
	my $donesize = 0;


	$input->{'STARTBLOB'} = 0;
	$input->{'ENDBLOB'} = 0;

	my $answer;
	$answer->{'STARTBLOB'} = 0;
	$answer->{'ENDBLOB'} = 0;

	my ($s1,$w1,$t1) = ($this->ID->[0],$this->ID->[1],$this->ID->[2]);
	return undef unless $s1 && $w1 && $t1;
	my $requestString = qq/type=MDECRYPT
JSON=$jsontext
ID=[$s1;$w1;$t1]/;
	my $startblob = qq/---STARTBLOB---/;
	my $endblob = qq/---ENDBLOB---/;
	
	my @msglines = split("\n",$requestString);
	my $linecount = 0;
	my $NumOfLines = scalar(@msglines);

	# send the first line (size BufferSize = 8192)
	print $socket $msglines[0]."\n";
	$linecount++;

	# this is for when the kgc still has to talk, but the client has finished
	while( my $line = <$socket> ){
		chomp($line);
		$line =~ s/SESSIONNEWLINERN/\r\n/g;
		$line =~ s/SESSIONNEWLINEN/\n/g;
		#print "Received Message:\n";#$line\n";
		my $response;
		# ................send in the cipher text to the kgc..................
		if($linecount < $NumOfLines){
			# start sending the header information
			$response = $msglines[$linecount];
			$linecount++;
		}
		elsif($linecount >= $NumOfLines && $input->{'STARTBLOB'} != 1){
			# send the star blob message
			$response = $startblob;
			$input->{'STARTBLOB'} = 1;
		}
		elsif($linecount >= $NumOfLines && $input->{'STARTBLOB'} == 1 && $input->{'ENDBLOB'} != 1 && read($fhcpr,$response,$BufferSize) != 0){
			# we are in the middle of a binary run
			$donesize += $BufferSize;
		}
		elsif($input->{'ENDBLOB'} != 1){
			# we finished sending the cipher text, send endblob to kgc
			$response = $endblob;
			$input->{'ENDBLOB'} = 1;
		}
		elsif($input->{'ENDBLOB'} == 1){
			# we are waiting for clear text from the kgc
			$response = "more";

		}


		#print "predom\n";
		# ................read in the clear text from the kgc..................
		# put JSON reader here
		if($line =~ m/^$startblob$/){
			$answer->{'STARTBLOB'} = 1;
		}
		elsif($answer->{'STARTBLOB'} == 1 && $line !~ m/^$endblob$/ && $answer->{'ENDBLOB'} != 1 ){
			# we are in the middle of a message
			# scoop the cipher text
			my $templine = $line;
			#$templine =~ s/MENCRYPTNEWLINE/\n/g;
			#$templine = decode_base64($templine);

			print $fhmsg $templine;
		}
		elsif($line =~ m/^$endblob$/){
			$answer->{'ENDBLOB'} = 1;
		}
		elsif($line eq "KGC Finished"){
			# KGC has indicated that the connection is over.
			last;	
		}		
		#$response =~ s/\n/MENCRYPTNEWLINE/g;
		#print "postdom($response)($line)\n";

		$response =~ s/\r\n/SESSIONNEWLINERN/g;
		$response =~ s/\n/SESSIONNEWLINEN/g;
		print $socket "$response\n";
	}
	# close the file handle
	close($fhcpr);
	close($fhmsg);
	return $answer;
}


=pod
---++ signature($sha256sum)->gpg signature
This is needed for authentication when uploading fileblobs.
=cut
sub signature {
	my $this = shift;
	my $hash = shift;
	my $cleanhash;
	# make sure the hash has no carriage returns
	if($hash =~ m/^(.[a-zA-Z0-9]+)$/){
		$cleanhash = $1;
	}
	else{
		die "no go";
	}
	my $signature;

	# now with the clean hash, let's go to the kgc
	my $socket = IO::Socket::UNIX->new(
   Type => SOCK_STREAM,
   Peer => $this->{'kgc_socket_path'},
)
   or die("Can't connect to server: $!\n");
	
	# print the type first
	print $socket "type=HASHSIGN\n";
	
	my $counter = 0;
	while( my $line = <$socket> ){
		chomp($line);
		$line =~ s/SESSIONNEWLINERN/\r\n/g;
		$line =~ s/SESSIONNEWLINEN/\n/g;
		#print "KGC:$line\n";
		my $response = "more";
		
		if($counter == 0){
			# print the hash
			$response = "hash=[$cleanhash]";
			$counter++;
		}
		elsif($line eq 'KGC Finished' ){
			# kgc is about to close the connection, so don't print anything
			$response = undef;
		}
		else{
			# we should have received the GPG signature by now
			$signature = $line;
			# tell the kgc we are finished
			$response = "END";
		}
		
		if($response){
			print $socket "$response\n";
		}
	}
	# we need to format the signature
=pod
-----BEGIN PGP SIGNATURE-----
Version: GnuPG v2.0.14 (GNU/Linux)

iQEcBAABAgAGBQJRkb/4AAoJEDyNLVSIBJuskAAIAOJj1fM6t30pRLQ9JWLFuy5Y
rTFzZ1rP6yfoO1+pomTqph3MgmCUQTDSeIP4+wPT6PlW/I7SyUxvtpi1YO0of69n
OrGs8cqSJwtvcFemefYec4SBrQN6izPHvfcGSIpa+bxNPkVVzr+yGFBNzIw7tfUk
O8J2/3wENPcLMYco79N7oIZniLFQMxUNvEQ16s9bfYFthSLXANcvOE6F3eiwJ20k
xDu9yOtMOYk65mA2fPDLZUMTu4GUl6TUkp6yaOVoLO5lYit+ZSg54Y+BeJt2zsZe
+bMruLAxUXnsJnXA0Ik8sF956O0K3BwbR1Y1+HuoONFNY/fMK/JjOrKTzKuzE7Q=
=Bwl3
-----END PGP SIGNATURE-----
=cut
	my @returnsig;
	foreach my $line (split("\n",$signature)){
		if($line eq '-----BEGIN PGP SIGNATURE-----' || $line eq '-----END PGP SIGNATURE-----'){
			next;
		}
		elsif($line =~ m/^Version:/){
			next;
		}
		elsif($line){
			push(@returnsig,$line);
		}
	}
	$signature = join('HASHSIGNNEWLINE',@returnsig);
	#print "old:$signature\n";
	# search and replace / and + and =
	$signature =~ s/\//SLASH/g;
	$signature =~ s/\+/PLUS/g;
	$signature =~ s/=/EQUAL/g;
	return $signature;
}


=pod
---++ upload()
This uploads the cipher text to E-Flamingo's webserver.  
=cut


sub upload {
	my $this = shift;

	my $filepath = $this->{'file_path'};

	my $output = "";


	my $uploaddir = "$filepath/upload";
	`mkdir -p $uploaddir` unless -d $uploaddir;

	# copy meta data (any file in the 'filepath') into the Upload folder
	opendir(my $bb, "$filepath") || die "Can't opedir $filepath: $!\n";
	my @tmplist = readdir($bb);
	foreach my $metafile (@tmplist){
		$filepath =~ /^(.*)$/ && ($filepath = $1);
		$metafile =~ /^(.*)$/ && ($metafile = $1);
		$uploaddir =~ /^(.*)$/ && ($uploaddir = $1);
		# the "info" file is an exception, we don't upload that
		`cp $filepath/$metafile $uploaddir/` if -f "$filepath/$metafile" && $metafile ne 'info';
	}
	closedir($bb);

	# upload the payload file first
	my $symmetricKey = $this->_payloadUpload();



	@tmplist = ();

	my @list;
	# find all of the files in pieces
	opendir(D, "$filepath/upload") || die "Can't opedir $filepath/upload: $!\n";
	@tmplist = readdir(D);
	foreach my $subdir (@tmplist){

		next if $subdir eq '.' || $subdir eq '..';
		
		if(-f "$filepath/upload/$subdir"){
			# then this is a file, not subdirectory
			$this->_individualUpload("$filepath/upload/$subdir",$symmetricKey);
		}
		else{
			# this is a directory, get the subdirectories
			opendir(DE, "$filepath/upload/$subdir") || die "Can't opendir\n";
			my @subtmplist = readdir(DE);
			foreach my $filesubdir (@subtmplist){
				next if $filesubdir eq '.' || $filesubdir eq '..';
				$this->_individualUpload("$filepath/upload/$subdir/$filesubdir",$symmetricKey);
			}
			closedir(DE);
		}
	}
	closedir(D);
	push(@list,@tmplist) if scalar(@tmplist) > 0;

	return "happy";
}
=pod
---+++ _payloadUpload()->Symmetric Key
This function informs the Mothership as to what files are going to be uploaded, and the symmetric key that will be used to encrypt traffic over http.
=cut

sub _payloadUpload {
	my $this = shift;
	my $filepath = $this->{'file_path'};
	my ($oldInfoFP,$uploadInfoFP) = ($filepath.'/info',$filepath.'/info.upload');
	my $output;

	# create a new info.upload
	return undef unless -f $oldInfoFP; # <-- checks if info file actually exists, which it should if this function is being called
	$output = `cp $oldInfoFP $uploadInfoFP`;

	# start adding extra information
	
	# 1. add the symmetric key that will be used to upload the rest of the files
	my $symmetricKey = $this->_randomPassword(60);
	$output = `echo "$symmetricKey" >> $uploadInfoFP`;
	# 2. add the sha256sum of all the files in the upload directory
	# ... put the filepath relative to the upload folder	
	# -maxdepth 2
	$output = ` find $filepath/upload/ -name '*'  -type f -exec sha256sum {} 2>/dev/null \\; >> $uploadInfoFP`;

	# search and replace filepath from sha256sum calculation
	my $newfilepath = $filepath.'/upload/';
	$newfilepath =~ s/\//\\\//g;
	#print "FP:$newfilepath\n";
	` sed -i 's/$newfilepath//g' $uploadInfoFP`;

	#print `cat $uploadInfoFP`;

	# let's get the hash
	my $hash = "";
	my $tmp = `sha256sum $uploadInfoFP`;
	if($tmp =~ m/^([a-z0-9]+)/){
		$hash = $1;
	}
	else{
		return undef;
	}	

	# get the signature for this payload file
	my $signature = $this->signature($hash);

	# upload the payload file along with a timestamp
	my $time = time();

	# this bash command is confirmed as to work
	# echo "Chello, I am here in this curly place, gosh darn it motherfudger." | gpg2 --homedir flsdjfjefe --trusted-key E73FC2C034258836 -r ms-001@octops.e-flamingo.net --armor -se 2>/dev/null | curl -v -F filename=@- -F action=payload http://www.example.com/test.pl
	my $mothershipR = 'ms-001@octops.e-flamingo.net';
	my $rootID = $Foswiki::cfg{rootID};

	# untaint necessary variables
	$uploadInfoFP =~ /^(.*)$/ && ($uploadInfoFP = $1);
	$rootID =~ /^(.*)$/ && ($rootID = $1);
	$mothershipR =~ /^(.*)$/ && ($mothershipR = $1);
	$signature =~ /^(.*)$/ && ($signature = $1);
	$hash =~ /^(.*)$/ && ($hash = $1);
	
	my $gnupgDir = $Foswiki::cfg{GnuPGDir};


	$output = `cat $uploadInfoFP | gpg2 --homedir $gnupgDir --trusted-key $rootID -r $mothershipR --armor -e 2>/dev/null | curl -v -F filename=\@- -F action=payload -F signature=$signature -F hash=$hash http://www.example.com/test.pl `;
		
	if($output =~ m/Hi/){
		# TODO:check to see if this fileblob has already been uploaded 
		#return 0;
	}


	#print "Sig:($signature)\nHash:($hash)\n---Curl Output---\n$output\n---DONE---\n";
	# the first to lines of the output are to be ignored.
	my @op = split("\n",$output);
	shift(@op);
	shift(@op);

	my $tmpdownload = time();
	open ( DOWNLOADFILE, ">> $filepath/$tmpdownload " ) or die "$!";
	print DOWNLOADFILE join("\n",@op);
	close DOWNLOADFILE;

	# the message is clearsigned by the mothership, so when gpg "decrypt" is run, we are just stripping the cleartext
	my $message = `cat $filepath/$tmpdownload  | openssl aes-256-cbc -pass pass:$symmetricKey -salt -d |  gpg2 --homedir $gnupgDir --trusted-key $rootID --decrypt 2>/dev/null `;

	`rm $filepath/$tmpdownload`;

	# let us find out if the symmetric key makes any sense, if not, then there is someone snooping in a MITM
	# ...TODO: parse $message without executing it and using any JSON libraries
	my $downloadedSymmetricKey = "";
	foreach my $line (split("\n",$message)){
		if($line =~ m/\s+'symmetric_key'\s+=>\s+'([a-zA-Z0-9]+)'/){
			$downloadedSymmetricKey = $1;
		}
	}
	die "Mothership did not respond with the correct Symmetric Key" if $downloadedSymmetricKey eq "";
	return $symmetricKey;
}


sub _individualUpload {
	my $this = shift;
	my $filepath = shift;
	my $symmetricKey = shift;
	# check if this file exists
	
	my $rootID = $Foswiki::cfg{rootID};
	$rootID =~ /^(.*)$/ && ($rootID = $1);

	return undef unless -f "$filepath";
	#die "nothing";
	my $key = $this->key;
	
	my $wezi = 'ardhi-daikyocho@e-flamingo.net';
	my $ms = 'http://www.example.com/test.pl';
	my $msAddress = 'ms-001@octops.e-flamingo.net';
	my $gnupgDir = $Foswiki::cfg{GnuPGDir};

	# encrypt the SymmetricKey (which functions as the "password" authentication with the Mothership)
	# ...the SymmetricKey also ties this upload with the correct FileBlob (whoes payload file has already
	# ......been uploaded)
	my @GPGMSG = split("\n",` echo "$symmetricKey" | gpg2 --homedir $gnupgDir --trusted-key $rootID -r $msAddress --armor -e 2>/dev/null`);
	shift(@GPGMSG);
	shift(@GPGMSG);
	pop(@GPGMSG);
	my $gpgMsg = join("\n",@GPGMSG);
	$gpgMsg =~ s/\n/HASHSIGNNEWLINE/g;
	$gpgMsg =~ s/\//SLASH/g;
	$gpgMsg =~ s/\+/PLUS/g;
	$gpgMsg =~ s/=/EQUAL/g;

	#print "Upload String:\n\ncurl -v -F filename=\@- -F action=upload -F key=$key -F symmetric=$gpgMsg http://www.example.com/test.pl\n\n";
	# upload the file
	# ... this bash command works echo "MyPass34" | openssl aes-256-cbc -pass stdin -salt -in /tmp/life.txt | openssl aes-256-cbc -pass pass:MyPass34 -salt  -d
	# ... but first, we must untaint many variables
	$symmetricKey =~ /^(.*)$/ && ($symmetricKey = $1);
	$filepath =~ /^(.*)$/ && ($filepath = $1);
	$key =~ /^(.*)$/ && ($key = $1);
	$gpgMsg =~ /^(.*)$/ && ($gpgMsg = $1);

	my $output = `echo "$symmetricKey" | openssl aes-256-cbc -pass stdin -salt -in $filepath | curl -v -F filename=\@- -F action=upload -F key=$key -F symmetric=$gpgMsg http://www.example.com/test.pl`;
	#my $output = `curl -v -F action=upload -F filename=\@$filepath -F hash=$hash -F signature=$signature -F wezi=$wezi $ms`;
	# curl -v -F filename=@blobname -F hash=$hash -F signature=$sig -F wezi=ardhi-daikyocho@e-flamingo.net
	#;
	return $output;
}

=pod
---++ Foswiki::Contrib::DBIStoreContrib::FileBlob::verifyTOPT
   * time? not necessary...
   * topt - code entered by user
   * user_id (UUID, not the email address)

Retrieve signature from the Mothership.  This function does not check passwords, just assumes the user entered the correct password.
=cut
sub verifyTOPT {
	my $this = shift;
	my ($topt,$userid) = (shift,shift);
	my $time = time();

	# get the location of session_id directory
	my $fdir = $this->{'file_directory'}.'/sessions';
	`mkdir -p $fdir` unless -d $fdir;
	
	# user_id in UUID hyphen hexadecimal format
	die "User ID is not a UUID!" unless $userid =~ m/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/;
	$userid =~ /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/ && ($userid = $1);

	# TODO:Find the TOPT token in order to check TOPT
	# blah.... lookup($userid);

	die "TOPT is not an integer!" unless $topt =~ m/[0-9]{6}/;
	$topt =~ /^([0-9]{6})$/ && ($topt = $1);
	$time =~ /^([0-9]+)$/ && ($time = $1);

	# TODO: add variable for Session Time. default to 2 hours
	my $lengthtime = $time + 2*60*60;	

	#"$topt\n$time\n$lengthtime\n$userid"
	my $file = qq{TIME:FROM[$time]TO[$lengthtime]
TOPT:[$topt]
USERID:[$userid]};
#  \"TIME:$time\\nTOPT:$topt\\nUSERID:$userid\\nSIGNATURE:$signature\\n\
	my $filehash = sha256_hex($file);
	# returns single line GPG signature
	my $signature = $this->signature($filehash);
	$signature =~ /^(.*)$/ && ($signature = $1);
	
	# append signature
	$file .= qq{
SIGNATURE:[$signature]};
	# now, in order to prep for upload, replace newlines with fake newlines (b/c of bash command)
	$file = join('\n',split("\n",$file));
	$file =~ /^(.*)$/ && ($file = $1);

	# set the session_id save location
	my $sessionFP = $fdir.'/'.$filehash;

	my @mothership = @{$this->findMotherShip()};
	shift(@mothership);
	my $Keyref = $this->generateSessionKey(@mothership);
	die "generateSessionKey failed!" unless ref($Keyref) == 'ARRAY';
	my ($gpgSE,$symmetricKey) = @{$Keyref};

#	my $MotherShipSignature = ` wget -O - "http://www.example.com/test.pl?action=verifyTOPT&topt=$topt&user_id=$userid&signature=$signature&time=$time" 2>/dev/null | cat`;

	# send the symmetric key as a url param, then upload a gpg file containing session parameters

	$symmetricKey =~ /^(.*)$/ && ($symmetricKey = $1);
	$sessionFP =~ /^(.*)$/ && ($sessionFP = $1);

	$gpgSE =~ /^(.*)$/ && ($gpgSE = $1);

	open(my $fh, "echo -e \"$file\" | openssl aes-256-cbc -pass pass:$symmetricKey -salt | curl -F sessionfile=\@- -F action=verifyTOPT -F symmetric=$gpgSE http://www.example.com/test.pl | openssl aes-256-cbc -pass pass:$symmetricKey -salt -d |") || die "cannot do upload of session variables!";
	my $MotherShipSignature = "";
	while( my $lll = <$fh>){
		$MotherShipSignature .= $lll;
	}
	close $fh;

	# for testing change signature to gpg
	
	my $gpgMSSig = qq{-----BEGIN PGP SIGNATURE-----
Version: GnuPG v2.0.14 (GNU/Linux)

REPLACEME
-----END PGP SIGNATURE-----};
	$signature =~ s/HASHSIGNNEWLINE/\n/g;
	$signature =~ s/SLASH/\//g;
	$signature =~ s/PLUS/+/g;
	$signature =~ s/EQUAL/=/g;
	$gpgMSSig =~ s/REPLACEME/$signature/g;


	#die "Mother:($filehash)\nGPGSIG:($gpgMSSig)\n($MotherShipSignature)";
	my @mssig = split("\n",$MotherShipSignature);

	# TODO: check to see if the mothership signature is actually legitimate
	if($mssig[0] eq '-----BEGIN PGP SIGNATURE-----'){
		# we got a signature of this session from a Mothership
		# store it with a sha256sum hash
		return $MotherShipSignature;
	}
	elsif($mssig[0] eq 'Incorrect TOPT'){
		return -1;
	}
	else{
		# log in was a failure, this session will not be recognized
		return 0;
	}
}


=pod
---++ generateSessionKey($msaddress,$fingerprint)->\(gpg signature and encryption of symmetric key, symmetric key)
This is needed for when a Wezi wants to establish an encrypted connection with a mothership.
=cut
sub generateSessionKey {
	my $this = shift;
	my ($msaddress,$fingerprint) = (shift,shift);

	die "no address or fingerprint" unless defined $msaddress && defined $fingerprint;
	my ($gpgSE,$symmetricKey);

	# now with the clean hash, let's go to the kgc
	my $socket = IO::Socket::UNIX->new(
   Type => SOCK_STREAM,
   Peer => $this->{'kgc_socket_path'},
)
   or die("Can't connect to server: $!\n");
	
	# print the type first
	print $socket "type=MSSESSIONKEY\n";
	
	my $counter = 0;
	while( my $line = <$socket> ){
		chomp($line);
		$line =~ s/SESSIONNEWLINERN/\r\n/g;
		$line =~ s/SESSIONNEWLINEN/\n/g;

		my $response = "more";
		
		if($counter == 0){
			$response = "MSADDRESS=[$msaddress]";
			$counter++;
		}
		elsif($counter == 1){
			$response = "MSFINGERPRINT=[$fingerprint]";
			$counter++;
		}
		
		if($line eq 'KGC Finished' ){
			# kgc is about to close the connection, so don't print anything
			$response = undef;
		}
		elsif($line =~ m/^KEY=\[(.*)\]/){
			$symmetricKey = $1;
			# leave response as "more"
		}
		elsif($line =~ m/^-----BEGIN PGP MESSAGE-----/){
			# we should have received the GPG signature by now
			$gpgSE = $line;
			# tell the kgc we are finished
			$response = "END";
		}
		
		if($response){
			print $socket "$response\n";
		}
	}
	# we need to format the signature
=pod
-----BEGIN PGP MESSAGE-----
Version: GnuPG v2.0.14 (GNU/Linux)

iQEcBAABAgAGBQJRkb/4AAoJEDyNLVSIBJuskAAIAOJj1fM6t30pRLQ9JWLFuy5Y
rTFzZ1rP6yfoO1+pomTqph3MgmCUQTDSeIP4+wPT6PlW/I7SyUxvtpi1YO0of69n
OrGs8cqSJwtvcFemefYec4SBrQN6izPHvfcGSIpa+bxNPkVVzr+yGFBNzIw7tfUk
O8J2/3wENPcLMYco79N7oIZniLFQMxUNvEQ16s9bfYFthSLXANcvOE6F3eiwJ20k
xDu9yOtMOYk65mA2fPDLZUMTu4GUl6TUkp6yaOVoLO5lYit+ZSg54Y+BeJt2zsZe
+bMruLAxUXnsJnXA0Ik8sF956O0K3BwbR1Y1+HuoONFNY/fMK/JjOrKTzKuzE7Q=
=Bwl3
-----END PGP MESSAGE-----
=cut
	my @returnsig;
	foreach my $line (split("\n",$gpgSE)){
		if($line eq '-----BEGIN PGP MESSAGE-----' || $line eq '-----END PGP MESSAGE-----'){
			next;
		}
		elsif($line =~ m/^Version:/){
			next;
		}
		elsif($line){
			push(@returnsig,$line);
		}
	}
	$gpgSE = join('HASHSIGNNEWLINE',@returnsig);
	#print "old:$signature\n";
	# search and replace / and + and =
	$gpgSE =~ s/\//SLASH/g;
	$gpgSE =~ s/\+/PLUS/g;
	$gpgSE =~ s/=/EQUAL/g;

	my @returnArray = ($gpgSE,$symmetricKey);
	return \@returnArray;
}

=pod
---+++ findMotherShip()->\(url,email address,gpg fingerprint)
This function will do a round robin to find out what the latest sets of motherships are, and pick one that is least loaded with the best ping time.
=cut
sub findMotherShip {
	my $this = shift;

	my @answer = ('http://www.example.com/test.pl',
		'ms-001@octops.e-flamingo.net','96B21F2AFAE2D950A9E4CFEFCB84AF5EB21F3CA6');
	return \@answer;
}

=pod
---++ Extra functions

=cut

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
        $password_length = 50;
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


