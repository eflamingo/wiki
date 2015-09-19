use DBI	();
use Digest::SHA  ();
use Digest::SHA1 ();
use MIME::Base64();
use Data::UUID ();
use Data::Dumper();
use Encode ();

use utf8;

my $sqlinstxt = {};




=pod
---+ SQL
---++ Define SQL Statements
=cut
$sqlinstxt->{'_NonTopic'} = {
	'Webs' => 1,
	'Web_History' => 1,
	'Sites' => 1,
	'Site_History' => 1
};

$sqlinstxt->{'Webs'} = {
	'key' => {'type' => 'uuid' },
	'link_to_latest' => {'type' => 'uuid' },
	'web_name' => {'type' => 'text' },
	'site_key' => {'type' => 'uuid' },
	'web_preferences' => {'type' => 'uuid' },	
	'web_home' => {'type' => 'uuid' },
	'_order' => [
		'key','web_name','web_home','web_preferences'
	],
	'_sql' => 'INSERT INTO wiki."Webs" (COLUMNS) 
		VALUES (QUESTIONS)',
	'_sqlorder' => ['key','web_name','web_home','web_preferences','site_key','link_to_latest'] 

};
$sqlinstxt->{'Web_History'} = {
	'key' => {'type' => 'uuid' },
	'web_key' => {'type' => 'uuid' },
	'start_time' => {'type' => 'uuid' },
	'owner_group' => {'type' => 'text' },
	'permissions' => {'type' => 'integer' },
	'site_history_key' => {'type' => 'uuid' },
	'_order' => [
		'site_history_key','web_key','start_time','owner_group','permissions'
	],
	'_sql' => 'INSERT INTO wiki."Web_History" (COLUMNS)
		VALUES (QUESTIONS)',
	'_sqlorder' => [
		'site_history_key','web_key','start_time','owner_group','permissions','key'
	]
};

$sqlinstxt->{'Sites'} = {
	'key' => {'type' => 'uuid' },
	'link_to_latest' => {'type' => 'uuid' },
	'site_name' => {'type' => 'text' }, # <-- change to site_name
	'local_preferences' => {'type' => 'uuid' }, 
	'default_preferences' => {'type' => 'uuid' } ,
	'site_home' => {'type' => 'uuid' },
	'admin_user' => {'type' => 'uuid' },
	'admin_group' => {'type' => 'uuid' },
	'system_web' => {'type' => 'text' }, 
	'trash_web' => {'type' => 'text' } ,
	'home_web' => {'type' => 'uuid' },
	'guest_user' => {'type' => 'uuid' },
	'public_parameters' => {'type' => 'text' }, # <--PBC stuff
	'_order' => [
		'key','site_name','public_parameters','site_home','admin_user','guest_user',
		'admin_group','system_web','trash_web','home_web','local_preferences',
		'default_preferences'
	],
	'_sql' => 'INSERT INTO wiki."Sites" (COLUMNS) 
		VALUES (QUESTIONS) ',
	'_sqlorder' => [
		'key','site_name','public_parameters','site_home','admin_user','guest_user',
		'admin_group','system_web','trash_web','home_web','local_preferences',
		'default_preferences'
	] 

 
};

$sqlinstxt->{'Site_History'} = {
	'key' => {'type' => 'uuid' },
	'site_key' => {'type' => 'uuid' },
	'start_time' => {'type' => 'uuid' },
	'owner_key' => {'type' => 'text' }, # <-- GPG key input
	'owner_group' => {'type' => 'text' }, # <-- merkle root
	'permissions' => {'type' => 'integer'},
	'_order' => [
		'site_key','owner_key','owner_group','start_time','permissions'
	],
	'_sql' => 'INSERT INTO wiki."Site_History" (COLUMNS)
		VALUES (QUESTIONS)',
	'_sqlorder' => [
		'site_key','owner_key','owner_group','start_time','permissions','key'
	]
};

$sqlinstxt->{'Topics'} = {
	'key' => {'type' => 'uuid' },
	'link_to_latest' => {'type' => 'uuid' },
	'current_web_key' => {'type' => 'uuid' }, 
	'current_topic_name' => {'type' => 'bytea' },
	# Topics are not going to be saved to file, only Topic_History
	'_sql' => 'INSERT INTO wiki."Topics" (COLUMNS) VALUES (QUESTIONS)',
	'_sqlorder' => ['key','current_web_key','current_topic_name','link_to_latest']
};
$sqlinstxt->{'Topic_History'} = {
	'key' => {'type' => 'uuid' },
	'topic_key' => {'type' => 'uuid' },
	'user_key' => {'type' => 'uuid' }, 
	'revision' => {'type' => 'integer' },
	'web_key' => {'type' => 'uuid' },
	'timestamp_epoch' => {'type' => 'integer' },
	'topic_content' => {'type' => 'bytea' },
	'topic_name' => {'type' => 'bytea' },
	'owner' => {'type' => 'uuid' },
	'group' => {'type' => 'uuid' },
	'permissions' => {'type' => 'integer' },
	'_order' => [
		'topic_key','user_key','web_key','timestamp_epoch','topic_content','topic_name',
		  'owner','group','permissions'
	],
	'_sql' => 'INSERT INTO wiki."Topic_History" (COLUMNS)
		VALUES (QUESTIONS)',
	'_sqlorder' => [
		'topic_key','user_key','web_key','timestamp_epoch',
		  'owner','group','permissions','key','topic_content','topic_name'
	]
};

$sqlinstxt->{'Blob_Store'} = {
	'key' => {'type' => 'integer' },
	'number_vector' => {'type' => 'numeric' }, #<-- change to login name
	'value_vector' => {'type' => 'tsvector' },
	'summary' => {'type' => 'text' },
	'value' => {'type' => 'text' },
	'_sql' => 'INSERT INTO wiki."Blob_Store" (COLUMNS) VALUES (QUESTIONS)',
	'_sqlorder' => ['key','value']
};
=pod
---+++ Topics Dependents
=cut
$sqlinstxt->{'_Topic_Dependents'} = {
	'Groups' => 1,
	'Users' => 1
};

$sqlinstxt->{'Groups'} = {
	'key' => {'type' => 'uuid' },
	'site_key' => {'type' => 'uuid' }, # <-- used to double check Group does not jump Sites
	'login_name' => {'type' => 'text'},
	'_order' => ['key','login_name'], # <--only login name is needed; key = topic_key
	'_sql' => 'INSERT INTO wiki."Groups" (COLUMNS) VALUES (QUESTIONS)',
	'_sqlorder' => ['key','login_name','site_key'] 
};

$sqlinstxt->{'Users'} = {
	'key' => {'type' => 'uuid' },
	'login_name' => {'type' => 'text' }, #<-- change to login name
	'site_key' => {'type' => 'uuid' },
	'_order' => ['key','login_name'],
	'_sql' => 'INSERT INTO wiki."Users" (COLUMNS) VALUES (QUESTIONS)',
	'_sqlorder' => ['key','login_name','site_key']
};
 
=pod
---+++ Topic_History Dependents
=cut

$sqlinstxt->{'Dataform_Data_Field'} = {
	'key' => {'type' => 'uuid' },
	'topic_history_key' => {'type' => 'uuid' }, 
	'definition_field_key' => {'type' => 'uuid' },
	'field_value' => {'type' => 'bytea' },
	'_sql' => 'INSERT INTO wiki."Dataform_Data_Field" (COLUMNS) VALUES (QUESTIONS)',
	'_sqlorder' => ['topic_history_key','definition_field_key','field_value']
};

$sqlinstxt->{'Dataform_Definition_Field'} = {
	# field_key is derived on the spot
	'key' => {'type' => 'uuid' },
	# thkey is implied from file path (inside topic_revision file_blob)
	'topic_history_key' => {'type' => 'uuid' }, 
	'field_name' => {'type' => 'bytea' },
	'field_type' => {'type' => 'text' },
	'other_info' => {'type' => 'bytea' },
	'_order' => ['topic_history_key','field_name','field_type','other_info'],
	# so, basically, we only have to store a blob key which contains
	# .. the field_name, field_type, other_info => one row in wiki text of
	# .. field definition
	'_sql' => 'INSERT INTO wiki."Dataform_Definition_Field" (COLUMNS) VALUES (QUESTIONS)',
	'_sqlorder' => ['topic_history_key','field_name','field_type','other_info']
};

$sqlinstxt->{'Group_User_Membership'} = {
	'user_key' => {'type' => 'uuid' },
	'group_key' => {'type' => 'uuid' }, 
	'topic_history_key' => {'type' => 'uuid' },
	'_order' => ['topic_history_key','user_key','group_key'], # <-- no need for key, put here b/c of algo in _tableCalc
	'_sql' => 'INSERT INTO wiki."Group_User_Membership" (COLUMNS) VALUES (QUESTIONS)',
	'_sqlorder' => ['topic_history_key','user_key','group_key']
};

$sqlinstxt->{'Links'} = {
	'key' => {'type' => 'uuid' },
	'topic_history_key' => {'type' => 'uuid' }, 
	'link_type' => {'type' => 'text' }, 
	'destination_topic' => {'type' => 'uuid' },
	'destination_topic_history' => {'type' => 'uuid' },
	'blob_key' => {'type' => 'bytea' },
	'original_text' => {'type' => 'text' },
	# order = link_type, destination_topic_history, destination_topic
	'_order' => ['topic_history_key','link_type','destination_topic_history','destination_topic'],
	'_sql' => 'INSERT INTO wiki."Links" (COLUMNS) VALUES (QUESTIONS)',
	'_sqlorder' => ['topic_history_key','link_type','destination_topic_history','destination_topic'] 
};
# i think this should be MetaPreferences_History
$sqlinstxt->{'MetaPreference_History'} = {
	'key' => {'type' => 'uuid' },
	'topic_history_key' => {'type' => 'uuid' }, 
	'type' => {'type' => 'text' },
	'name' => {'type' => 'text' },
	'value' => {'type' => 'text' },
	'_order'=>['topic_history_key','type','name','value'],
	# careful! there was a spelling mistake in the tablename
	'_sql' => 'INSERT INTO wiki."MetaPreferences_History" (COLUMNS) VALUES (QUESTIONS)',
	'_sqlorder' => ['topic_history_key','type','name','value']
};

$sqlinstxt->{'User_History'} = {
	'key' => {'type' => 'uuid' },
	'first_name' => {'type' => 'text' },
	'last_name' => {'type' => 'text' },
	'login_name' => {'type' => 'uuid' }, #<-- this should never change??
	'password' => {'type' => 'text' },
	'timestamp_epoch' => {'type' => 'integer' },
	'email' => {'type' => 'text' },
	'country' => {'type' => 'text' , 'default' => 'USA'},
	'callback_number' => {'type' => 'text' }, # <-- international phone number
	'gpg_key' => {'type' => 'text' },
	'_order' => ['key','first_name','last_name','password','email','country',
		'callback_number'],
	'_sql' => 'INSERT INTO wiki."User_History" (COLUMNS) VALUES (QUESTIONS)',
	# this key is the topic_history_key
	'_sqlorder' => ['key','first_name','last_name','password','email','country',
		'callback_number']

};
=pod
---++ startNewdbiconnection() -> DBI->new

=cut
sub startNewdbiconnection {
	my $input = shift;
	# Setup all off of db_connections
	#  Note: dbconnection_read is for doing SELECT queries only, while dbconnection_write is for doing transactions
	my $DB_name = 'wikidb';
	my $DB_host = 'localhost';
	my $DB_user = 'wikidbuser';
	my $DB_pwd = 'put secret password here';	
	my $dbconnection = DBI->connect("dbi:Pg:dbname=$DB_name;host=$DB_host",$DB_user,$DB_pwd, {'RaiseError' => 1}) or return "DB Death!";
	$dbconnection->{AutoCommit} = 0;  # disable transactions
	
	# defer constraints
	my $deferStatement = qq{SET CONSTRAINTS ALL DEFERRED;};
	my $deferhandler = $dbconnection->prepare($deferStatement);
	#my $xo = Data::Dumper::Dumper($deferhandler);
	eval{
		$deferhandler->execute();
	};
	if($@){
		$dbconnection->disconnect();
		die "no good!\n$@\n";
	}
	# create handler for each input Table
	foreach my $TableName (keys %{$sqlinstxt}){
		next unless defined $sqlinstxt->{$TableName}->{'_sql'} &&
			defined $sqlinstxt->{$TableName}->{'_sqlorder'};
			
		my $insertStatement = $sqlinstxt->{$TableName}->{'_sql'};
		my @myCols = @{$sqlinstxt->{$TableName}->{'_sqlorder'}};

		my $columns = '"'.join('","',@myCols).'"';
		$insertStatement =~ s/COLUMNS/$columns/g;
		my @questions;
		foreach my $i0 (1..scalar(@myCols)){
			push(@questions,'?');
		}
		my $q001 = join(',',@questions);
		$insertStatement =~ s/QUESTIONS/$q001/g;
		$input->{'_DBI'}->{$TableName}->{'_handler'} = $dbconnection->prepare($insertStatement);
		#my $xo = Data::Dumper::Dumper($input->{'_DBI'}->{$TableName}->{'_handler'});
		#print "$TableName:\n$xo";
		
	} 

	return $dbconnection;
}
=pod
---++ executeDBI($input,$tablename,$Row)
Use this function to do the inserts
=cut
sub executeDBI {
	my ($input,$tablename,$Row) = @_;
	my $insertHandler = $input->{'_DBI'}->{$tablename}->{'_handler'};
	
	die "$tablename: No table!\n" unless $insertHandler;
	
	#my $xoo = Data::Dumper::Dumper($Row);
	#print "no column;\n$xoo\n";# if ! defined $Row->{'topic_content'} &&	$tablename eq 'Topic_History';
	
	# make sure we are not duplicating MetaPreference hits
	# ..a hack..
	if($tablename eq 'MetaPreference_History'){
		
		my $rowx = $Row->{'topic_history_key'}.$Row->{'type'}.$Row->{'name'};
		my $tmpbool = $input->{'mph_blobs'}->{$rowx};
		if($tmpbool){
			# don't insert a duplicate row
			return 0;
		}
		else{
			# proceed as normal
			$input->{'mph_blobs'}->{$rowx} = 1;
		}
	}

	

	my @myCols = @{$sqlinstxt->{$tablename}->{'_sqlorder'}};
	
	
	my $counter = 1;
	my @params;
	foreach my $mc1 (@myCols){
		if($Row->{$mc1} eq ''){
			$Row->{$mc1} = undef;
		}
		if($sqlinstxt->{$tablename}->{$mc1}->{'type'} eq 'bytea'){
			# decode the column as it is still in base64 
			
			$Row->{'integer'.$mc1} = $input->{'blobs'}->{decode($Row->{$mc1})}->{'integer'};
			#my $yoo = Data::Dumper::Dumper($input->{'fp'});
			#die "No matching Blob:".$Row->{$mc1}."\n". unless $input->{'blobs'}->{$Row->{$mc1}}->{'integer'} > 0;
			$insertHandler->bind_param( $counter, $input->{'blobs'}->{decode($Row->{$mc1})}->{'integer'});
			
		}
		else{
			$insertHandler->bind_param( $counter, $Row->{$mc1});
		}
		push(@params,$Row->{$mc1});
		$counter++;
	}
	
	eval{
		$insertHandler->execute();
	};
	if($@){
		my $yo1 = Data::Dumper::Dumper($Row);
		die "mofo!\n$yo1\n$@";
	}
	
}
=pod
---+ Scoopers

=cut
=pod
---++ scanBlobs
=cut
sub scanBlobs {
	my $input = shift;
	my $basefp = $input->{'file_path'};
	
	my $allblobstore = `find $basefp -name 'Blob_Store'`;
	my @allfilepaths;
	foreach my $bsfp (split("\n",$allblobstore)){
		opendir(my $fh,"$bsfp") || die "cannot open Blob_Store directory.\n";
		my @rdir = readdir($fh);
		closedir($fh);
		foreach my $rd1 (@rdir){
			next if $rd1 eq '.' || $rd1 eq '..' || ! (-f "$bsfp/$rd1");
			push(@allfilepaths,"$bsfp/$rd1");
		}
	}
	# This part is for Blob Keys
	# we need to scan all the blobs into memory
	$input->{'blobs'}->{'integer'} = 1;
	print "Integer Start:".$input->{'blobs'}->{'integer'}."\n";
	
	foreach my $fp1 (@allfilepaths){
		my $content = `cat $fp1`;
		my $contentkey = Digest::SHA1::sha1($content);
		
		# get the topic key
		my $topickey = "";
		my $fpnum;
		if($fp1 =~ m/\/([^\/]+)\/Blob_Store/){
			$fpnum = $1;
			$topickey = $input->{'fp'}->{$fpnum}->{'TopicKey'};
		}
		
		
		# we do this to make sure no two blobs have the same content
		$input->{'blobs'}->{'integer'} += 1;
		$input->{'blobs'}->{$contentkey}->{'integer'} = $input->{'blobs'}->{'integer'};
		
		# we do this b/c blobs are referenced via their merkleroot
		#print "Insert Blob:$fpnum\n";
		$input->{'blobs'}->{merkleroot($input->{'fp'}->{$fpnum}->{'TopicKey'},$content)}->{'integer'}	
			= $input->{'blobs'}->{$contentkey}->{'integer'};
		#print "key:".$input->{'blobs'}->{$contentkey}->{'integer'}."($contentkey)\n";
		_tableCalc_Blob_Store_THDependents($input,
			{'key' => $input->{'blobs'}->{$contentkey}->{'integer'},'value'=> $content});
	}
}


=pod
---++ scanInfo($fp)-> scan all *.info files
We need to map filepath to (sitehistorykey,webhistorykey,topickey).
=cut
sub scanInfo {
	my $input = shift;
	my $fp = shift;
	my ($shk,$whk,$topickey,$counter);
	$counter = 0;
	open(my $fh,'<',"$fp") || die "can't open info file.";
	while(my $line = <$fh>){
		$shk = $line if $counter == 0;
		$whk = $line if $counter == 1;
		$topickey = $line if $counter == 2;
		$counter++;
	}
	close $fh;
	# get the name of the fileblob
	my $fpname = "";
	if($fp =~ m/\/([^\/\.]+)\.info$/){
		#print "fileblob name:$1\n";
		$fpname = $1;
	}
	else{
		die "unexpected error scooping info files.\n";
	}
	
	
	if($shk =~ m/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/){
		$input->{'fp'}->{$fpname}->{'SiteHistoryKey'} = $1;
	}
	if($whk =~ m/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/){
		$input->{'fp'}->{$fpname}->{'WebHistoryKey'} = $1;
	}
	if($topickey =~ m/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/){
		$input->{'fp'}->{$fpname}->{'TopicKey'} = $1;
	}
	#print "FP:$fpname\n";
	# THIS section is b/c there are dead LINKS, we have to strip out
	# ..when we insert topic Links
	$input->{'topickeys'}->{$input->{'fp'}->{$fpname}->{'TopicKey'}} = 1
		if defined $input->{'fp'}->{$fpname}->{'TopicKey'};
	
	
}
=pod
---++ scanSites
=cut
sub scanSites {
	my $input = shift;
	my $hash = shift;
	my $baseFP = $input->{'file_path'}.'/'.$input->{'SiteName'};
	foreach my $fp (keys %{$hash}){
		my $blobFP ="$baseFP/$fp";
		
		opendir(my $fh,"$blobFP") || die "no directory($blobFP)!";
		my @innards = readdir($fh); 
		closedir($fh);
		foreach my $inner (@innards){
			next if $inner eq '.' || $inner eq '..' || -d "$blobFP/$inner";
			#print "Site:$inner\n";
			open(my $f1,'<',"$blobFP/$inner") || die "can't open file.";
			my @cArray = <$f1>;
			
			close $f1;
			if($inner eq 'Sites'){
				_tableCalc_Sites($input,\@cArray);
			}
			elsif($inner eq 'Site_History'){
				_tableCalc_Site_History($input,\@cArray);
			}
			elsif($inner eq 'Site_History.OwnerGroup'){
				_tableCalc_Site_History_OwnerGroup($input,\@cArray);
			}
			#print $hash->{$fp}->{$inner}."\n"; 
		}
	}
	
}
sub _tableCalc_Sites {
	my ($input,$contentref,$info) = @_;
	
	my @cArray = @{$contentref};
	my @cols = @{$sqlinstxt->{'Sites'}->{'_order'}};
	#die "(@cArray)\n(@cols)";
	# 'key','web_name','web_home','web_preferences'
	
	my $Row = {};
	foreach my $col (@cols){
		my $line = shift(@cArray);
		$line =~ s/\n//g;
		$Row->{$col} = $line;
	}	
	
	#$Row->{'key'} = merkleroot($tRow->{'topic_key'},$Row->{'value'});
	
	
	#my $xo = Data::Dumper::Dumper($Row);
	#print $xo;
	#die "Yo:($handler)\n(@myCols)";
	$input->{'wt'}->{'SITEKEY'} = $Row->{'key'};
	executeDBI($input,'Sites',$Row);


	return $Row;
}


sub _tableCalc_Site_History {
	my ($input,$contentref,$info) = @_;
	
	my @cArray = @{$contentref};
	my @cols = @{$sqlinstxt->{'Site_History'}->{'_order'}};
	#die "(@cArray)\n(@cols)";
	# 'key','web_name','web_home','web_preferences'
	
	my $Row = {};
	foreach my $col (@cols){
		my $line = shift(@cArray);
		$line =~ s/\n//g;
		$Row->{$col} = $line;
	}	
	my @input01;
	foreach my $in (@cols){
		push(@input01,$Row->{$in});
	}
	$Row->{'key'} = deriveUUID(@input01);
	
	
	#$Row->{'key'} = merkleroot($tRow->{'topic_key'},$Row->{'value'});
	my $xo = Data::Dumper::Dumper($Row);
	print "Site_History:\n(@input01)(@cols)\nSITEKEY:".$Row->{'site_key'}."\n";
	executeDBI($input,'Site_History',$Row);
	return $Row;
}
sub _tableCalc_Site_History_OwnerGroup {
	my ($input,$contentref,$info) = @_;
	
	my @cArray = @{$contentref};
	
	#die "(@cArray)\n(@cols)";
	# 'key','web_name','web_home','web_preferences'
	
	my $Row = {};
	my @io;
	foreach my $line (@cArray){
		$line =~ s/\n//g;
		push(@io,$line);
	}	
	$Row->{'Site_History.OwnerGroup'} = \@io;
	#$Row->{'key'} = merkleroot($tRow->{'topic_key'},$Row->{'value'});
	#my $xo = Data::Dumper::Dumper($Row);
	#die $xo;
	return $Row;
}

=pod
---++ scanWebs
=cut
sub scanWebs {
	my $input = shift;
	my $hash = shift;
	my $baseFP = $input->{'file_path'}.'/'.$input->{'SiteName'};
	foreach my $fp (keys %{$hash}){
		my $blobFP = "$baseFP/$fp";

		opendir(my $fh,"$blobFP") || die "no directory!";
		my @innards = readdir($fh); 
		closedir($fh);
		my $Row = {};
		foreach my $inner (@innards){
			
			next if $inner eq '.' || $inner eq '..' || -d "$blobFP/$inner";
			#print "Web:$inner\n";
			open(my $f1,'<',"$blobFP/$inner") || die "can't open file.";
			my @cArray = <$f1>;
			close $f1;
			if($inner eq 'Webs'){
				# we need the $blobFP in order to get the web_history_key for link_to_latest
				my $xr = _tableCalc_Web($input,\@cArray,$blobFP);
				foreach my $key (keys %{$xr}){
					$Row->{$key} = $xr->{$key};
				}
			}
			elsif($inner eq 'Web_History'){
				my $xr = _tableCalc_Web_History($input,\@cArray);
				foreach my $key (keys %{$xr}){
					$Row->{$key} = $xr->{$key};
				}
			}
			elsif($inner eq 'Web_History.OwnerGroup'){
				_tableCalc_Web_History_OwnerGroup($input,\@cArray);
			}
			#print $hash->{$fp}->{$inner}."\n"; 
		}
		
	}
	
}
sub _tableCalc_Web {
	my ($input,$contentref,$fp) = @_;
	
	my @cArray = @{$contentref};
	my @cols = @{$sqlinstxt->{'Webs'}->{'_order'}};

	# 'key','web_name','web_home','web_preferences'
	
	my $Row = {};
	foreach my $col (@cols){
		my $line = shift(@cArray);
		$line =~ s/\n//g;
		$Row->{$col} = $line;
	}	
	$Row->{'site_key'} = $input->{'wt'}->{'SITEKEY'};
	
	# need link_to_latest
	#die "Web fp:$fp\n";
	my $fpnum = "";
	if($fp =~ m/\/([^\/]+)$/){
		$fpnum = $1;
	}
	else{
		die "error trying to get fileblob name\n";
	}
	$Row->{'link_to_latest'} = $input->{'fp'}->{$fpnum}->{'WebHistoryKey'};
	my $yo = Data::Dumper::Dumper($Row->{'link_to_latest'});
	print "L2L:\n$yo\n";
	executeDBI($input,'Webs',$Row);
	return $Row;
}
sub _tableCalc_Web_History {
	my ($input,$contentref) = @_;
	
	my @cArray = @{$contentref};
	my @cols = @{$sqlinstxt->{'Web_History'}->{'_order'}};
	#my $webkeyCol = shift(@cols);
	#print "(@cArray)\n(@cols)\n";
	# 'key','web_name','web_home','web_preferences'
	
	my $Row = {};
	foreach my $col (@cols){
		my $line = shift(@cArray);
		$line =~ s/\n//g;
		$Row->{$col} = $line;
	}	
	my @input;
	foreach my $in (@cols){
		push(@input,$Row->{$in});
	}
	$Row->{'key'} = deriveUUID(@input);
	print "Web Array:\n@input\n";
	my $x11 = Data::Dumper::Dumper($Row);
	print "Web History:\n".$Row->{'key'}."\n";
	executeDBI($input,'Web_History',$Row);
	return $Row;
}

sub _tableCalc_Web_History_OwnerGroup {
	my ($input,$contentref,$info) = @_;
	
	my @cArray = @{$contentref};
	
	my @innards;
	foreach my $gpgemail (@cArray){
		$gpgemail =~ s/\n//g;
		push(@innards,$gpgemail);
	}
	$Row->{'OwnerGroupArray'} = \@innards;
	#my $x11 = Data::Dumper::Dumper($Row);
	#die "$x11";
	return $Row;
}
=pod
---++ scanTopics
=cut
sub scanTopics {
	my $input = shift;
	my $hash = shift;
	my $baseFP = $input->{'file_path'}.'/'.$input->{'SiteName'};
	foreach my $fp (keys %{$hash}){
		my $blobFP = "$baseFP/$fp";

		opendir(my $fh,"$blobFP") || die "no directory!";
		my @innards = readdir($fh); 
		closedir($fh);
		my ($tRow);
		foreach my $inner (@innards){
			next if $inner eq '.' || $inner eq '..' || -d "$blobFP/$inner";
			my $tablename = $inner;
			if($inner =~ m/^(.*)\.[0-9]*$/){
				# topic history dependency
				$tablename = $1;		
			}
			next unless $tablename eq 'Topic_History';
			open(my $f1,'<',"$blobFP/$inner") || die "can't open file.";
			my @contentArray = <$f1>;
			$hash->{$fp}->{$inner} = \@contentArray;
			close $f1;
			$tRow = _tableCalc_Topic_History($input,\@contentArray);
			#my $yo = Data::Dumper::Dumper($tRow);
			#print "$yo\n";
		}

		foreach my $inner (@innards){
			next if $inner eq '.' || $inner eq '..' || -d "$blobFP/$inner";
			
			my $tablename = $inner;
			if($inner =~ m/^(.*)\.[0-9]*$/){
				# topic history dependency
				$tablename = $1;		
			}
			next if $tablename eq 'Topic_History';
			open(my $f1,'<',"$blobFP/$inner") || die "can't open file.";
			my @contentArray = <$f1>;
			$hash->{$fp}->{$inner} = \@contentArray;
			close $f1;
			#print "$tablename\n".join('',@contentArray)."\n";
			
			# this line is to double check we are not scanning topics
			die "not a topic!\n" if $sqlinstxt->{'_NonTopic'}->{$tablename};
			
			my $topicbool = $sqlinstxt->{'_Topic_Dependents'}->{$tablename};
			
			_tableCalc_TopicDependents($blobFP,$input,$tablename,\@contentArray,$tRow)
				if $topicbool;
			_tableCalc_THDependents($blobFP,$input,$tablename,\@contentArray,$tRow)
				unless $topicbool;
			
		}
		opendir($fh,"$blobFP/Blob_Store") || die "no directory!";
		my @blobinnards = readdir($fh); 
		closedir($fh);
		foreach my $inner (@blobinnards){
			next if $inner eq '.' || $inner eq '..' || -d "$blobFP/Blob_Store/$inner";
			
			my $tablename = 'Blob_Store';
			
			open(my $f1,'<',"$blobFP/Blob_Store/$inner") || die "can't open file.";
			my @contentArray = <$f1>;
			$hash->{$fp}->{$inner} = \@contentArray;
			close $f1;
			#_tableCalc_Blob_Store_THDependents($input,$hash->{$fp}->{$inner},$tRow,$tablename);
		}
	}
	
}
sub _tableCalc_THDependents {
	my ($blobFP,$input,$tablename,$contentref,$tRow) = @_;
	die "No tablename!" unless defined $tablename;
	return _tableCalc_GUMembership_THDependents($input,$contentref,$tRow,$tablename)
		if $tablename eq 'Group_User_Membership';
	return undef
		if $tablename eq 'Blob_Store';
	return _tableCalc_Vanilla_THDependents($input,$contentref,$tRow,$tablename);
	
}
sub _tableCalc_TopicDependents {
	my ($blobFP,$input,$tablename,$contentref,$tRow) = @_;
	die "No tablename!" unless defined $tablename;
	
	return _tableCalc_Vanilla_TopicDependents($input,$contentref,$tRow,$tablename);
	
}

sub _tableCalc_Topic_History {
	my ($input,$contentref) = @_;
	my @cArray = @{$contentref};

	my $topicRow = {};
	my @cols = @{$sqlinstxt->{'Topic_History'}->{'_order'}};

	my $count = 0;
	my @keyArray;
	foreach my $line (@cArray){
		my $col = shift(@cols);
		my $x ="";
		if($line =~ m/^\n*(.*)\n*$/){
			$x = $1;
		}
		else{
			die "topic history not being read in properly";
		}
		# don't worry about bytea until executeDBI
		$topicRow->{$col} = $x;
		
		push(@keyArray,$x);
		
	}

	
	$topicRow->{'key'} = deriveUUID(@keyArray);
	#my $x11 = Data::Dumper::Dumper($topicRow);
	#print "Going out: $x11\n";
	executeDBI($input,'Topic_History',$topicRow);
	
	# now, we also have to store a row in Topics
	#'_sqlorder' => ['key','current_web_key','current_topic_name','link_to_latest']
	# copy the hash
	my $throw = {};
	$throw->{'key'} = $topicRow->{'topic_key'};
	$throw->{'link_to_latest'} = $topicRow->{'key'};
	$throw->{'current_topic_name'} = $topicRow->{'topic_name'};
	$throw->{'current_web_key'} = $topicRow->{'web_key'}; 
	executeDBI($input,'Topics',$throw);
	 
	return $topicRow;
}

sub _tableCalc_Vanilla_THDependents {
	my ($input,$contentref,$tRow,$tablename) = @_;
	my $topic_history_key = $tRow->{'key'};
	my @cArray = @{$contentref};
	
	my $Row = {};
	my @cols = @{$sqlinstxt->{$tablename}->{'_order'}};
	return undef unless scalar(@cols) > 0;
	my @keyArray;
	my $thkeyCol = shift(@cols);
	# 'key' = topic_history_key
	$Row->{$thkeyCol} = $topic_history_key;
	
	foreach my $col (@cols){
		my $line = shift(@cArray);
		chomp($line);
		# worry about bytea later in executeDBI
		$Row->{$col} = $line;
		

		push(@keyArray,$Row->{$col});
	}
	# we need to see if Links is dead or not
	if($tablename eq 'Links'){
		my $bool = 0;
		$bool = 1 if $input->{'topickeys'}->{$Row->{'destination_topic'}};
		#print "Dead Link\n" if $bool;
		return 0 unless $bool;
	}
	
	#$Row->{$thkeyCol} = deriveUUID(@keyArray);
	#my $x11 = Data::Dumper::Dumper($Row);
	#print "$tablename out: $x11\n" if $tablename =~ m/^Meta(.*)History$/;
	#die "noooo."  if $tablename =~ m/^Meta(.*)History$/;
	executeDBI($input,$tablename,$Row);
	return $Row;
}

sub _tableCalc_Blob_Store_THDependents {
	my ($input,$Row) = @_;
	
	executeDBI($input,'Blob_Store',$Row);
	return $Row;
}

sub _tableCalc_Vanilla_TopicDependents {
	my ($input,$contentref,$tRow,$tablename) = @_;
	my $topickey = $tRow->{'topic_key'};
	my @cArray = @{$contentref};
	print "Topic Dependent:$tablename\n";

	
	my $Row = {};
	my @cols = @{$sqlinstxt->{$tablename}->{'_order'}};
	return undef unless scalar(@cols) > 0;
	my @keyArray;
	my $topickeyCol = shift(@cols);
	$Row->{$topickeyCol} = $topickey;
	
	foreach my $col (@cols){
		my $line = shift(@cArray);
		chomp($line);
		
		
		# worry about bytea later in executeDBI
		$Row->{$col} = $line;
	
		push(@keyArray,$Row->{$col});
	
		
	}
	if(defined $sqlinstxt->{$tablename}->{'site_key'}){
		# add the site key because some tables have a site_key column
		# ..this won't effect key hash calculations
		$Row->{'site_key'} = $input->{'wt'}->{'SITEKEY'};
		# this implies site_key is always last in hash calculation
		push(@keyArray,$Row->{'site_key'});
	}
	
	#$Row->{$topickeyCol} = deriveUUID(@keyArray);
	
	executeDBI($input,$tablename,$Row);
	#my $x11 = Data::Dumper::Dumper($Row);
	#print "$tablename out: $x11\n"  if $tablename eq 'Users';
	return $Row;
}

sub _tableCalc_GUMembership_THDependents {
	my ($input,$contentref,$tRow,$tablename) = @_;
	my $topic_history_key = $tRow->{'key'};
	
	my $group_key = $tRow->{'topic_key'};
	
	my @cArray = @{$contentref};

	
	my @cols = @{$sqlinstxt->{$tablename}->{'_order'}};
	return undef unless scalar(@cols) > 0;
	my @keyArray;
	my $thkeyCol = shift(@cols);
	my $userCol = shift(@cols);
	my $groupCol = shift(@cols);
	my @rows;
	
	foreach my $line (@cArray){
		my $Row = {};
		$Row->{$thkeyCol} = $topic_history_key;
		$Row->{$groupCol} = $group_key;
		if($line =~ m/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/){
			$Row->{$userCol} = $1;
		}
		push(@rows,$Row) if defined $Row->{$userCol};
		die "no user key." unless  defined $Row->{$userCol};
	}
	#my $x11 = Data::Dumper::Dumper(@rows);
	#print "$tablename out: $x11\n" if $tablename eq 'Group_User_Membership';
	return @rows;
}


=pod
---+ Assitant Functions
=cut
sub deriveUUID {
	my @array = @_;
	#my $output = substr(Digest::SHA1::sha1_hex(join("\n",@array)),0,32 );
	my $output = Digest::SHA1::sha1_hex(join("\n",@array));
	
	my $uuid;
	if($output =~ m/^([0-9a-f]{8})([0-9a-f]{4})([0-9a-f]{4})([0-9a-f]{4})([0-9a-f]{12})/){
		$uuid = "$1-$2-$3-$4-$5";
	}
	die "no uuid." unless defined $uuid;
	return $uuid;
}
sub dhash {
	return Digest::SHA::sha256(Digest::SHA::sha256(shift));
}

sub encode {
	my $y = MIME::Base64::encode_base64(shift);
	if($y =~ m/(.*)\n$/){ $y = $1;}
	return $y;
}
sub encode_safe {
	my $y = encode(shift);
	$y =~ s/\//SLASH/g;
	$y =~ s/=/EQUAL/g;
	$y =~ s/\+/PLUS/g;
	return $y;
}
sub decode {
	return MIME::Base64::decode_base64(shift);
}

sub merkleroot {
	my @array = @_;

	my $length = scalar(@array);
	die "merkle fail.\n" unless $length > 0;

	my $depth = int(log($length)/log(2)) + 1;
	my @x;
	for (my $count = 0; $count < 2**$depth; $count++) {
		$x[$count] = dhash($array[$count]) if $count < $length;
		# repeat the last element until the lenght of the array
		# ..is a log of 2
		$x[$count] = $array[-1] unless $count < $length;
	}
	
	# start with the layer above the bottom one, and work towards the root
	# @x is initially loaded with the bottom values of the tree
	for (my $count = $depth-1; $count >= 0; $count--) {
		my @y;
		my $l = 2 ** $count; # <--should equal .5 * scalar(@x)
		for (my $c1 = 0; $c1 < $l; $c1++){
			$y[$c1] = dhash($x[2*$c1].$x[2*$c1+1]);
		}
		@x = @y;
	}
	die "merkle array failed.\n" unless scalar(@x) == 1;
	return $x[0];

}


=pod
---+ cycler
=cut

sub cycler{
	my $input = shift;
	my $SiteName = $input->{'SiteName'};
	my $fp = $input->{'file_path'};
	
	# site directory
	my $siteFP = "$fp/$SiteName";
	
	opendir(my $fh,"$siteFP") || die "no site directory!";
	my @fileblobs = readdir($fh);
	closedir($fh);
	
	# scan info
	foreach my $FileBlob (@fileblobs){
		next if -d "$fp/$SiteName/$FileBlob";
		scanInfo($input,"$fp/$SiteName/$FileBlob");
	}
	# blob store
	scanBlobs($input);
	
	# Find file paths to Site fileblob and then Web fileblobs
	my $sitesH = {};
	my $websH = {};
	my $topicsH = {};
	foreach my $kfp (keys %{$input->{'fp'}}){
		if(defined $input->{'fp'}->{$kfp}->{'TopicKey'}){
			# skip
			$topicsH->{$kfp} = $input->{'fp'}->{$kfp};
		}
		elsif(defined $input->{'fp'}->{$kfp}->{'WebHistoryKey'}){
			$websH->{$kfp} = $input->{'fp'}->{$kfp};
			#print "Web:$kfp\n";
		}
		elsif(defined $input->{'fp'}->{$kfp}->{'SiteHistoryKey'}){
			$sitesH->{$kfp} = $input->{'fp'}->{$kfp};
			#print "Site:$kfp\n";
		}
		else{
			# something weird is up
			# scuttle the program
			my $xo = Data::Dumper::Dumper($input->{'fp'}->{$kfp});
			die "Weird lack of ID($kfp).\n$xo\n";
		}
		
		
	}
	scanSites($input,$sitesH);
	scanWebs($input,$websH);
	scanTopics($input,$topicsH);
}

my $input01 = {
	'file_path' => '/tmp/wiki',
	'SiteName' => 'florida1986',
	'DBI' => $dbi
}; 
my $dbi = startNewdbiconnection($input01);
cycler($input01);
$dbi->commit;

$dbi->disconnect;

