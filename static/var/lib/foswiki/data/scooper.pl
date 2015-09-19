# this is a perl program
use Data::UUID			    ();
use Digest::SHA ();
use Digest::SHA1 ();
use MIME::Base64 ();
=pod
---+ Define Global Variables

Mount the new Site on ramfs.
mount -t tmpfs -o size=200m tmpfs /tmp/sites
=cut
my $wtmapper = {};
my $dump = '/home/joeldejesus/Workspace/foswiki-main/core/data/sites01';
my $COUNT = 0;

my $tmpDIR = '/home/joeldejesus/Workspace/florida1986';

my $siteinput = {
	'GPG' => {
		'dejesus.joel@gmail.com' => "NULL",
		'ardhi-florida@hw.e-flamingo.net' => "NULL",
		'ardhi-daikyocho@octops.e-flamingo.net' => "NULL"
	},
	'Main.Admin' => {
		'first_name' => 'Argentina',
		'last_name' => 'Rehe',
		'email' => 'tina.rehe@gmail.com',
		'password' => 'Nobrainer',
		'loginname' => 'tina.rehe',
		'country' => 'USA',
		'callback_number' => ''
	},
	'Sites' => {
		'SiteName' => 'florida1986',
		'OwnerGroup' => ['ardhi-florida@hw.e-flamingo.net',
		  'ardhi-daikyocho@octops.e-flamingo.net','dejesus.joel@gmail.com'],
		'Owner' => 'ardhi-florida@hw.e-flamingo.net',
		'PublicParameters' => "NULL",
		'pairing' => "NULL"
	},
	'Webs' => [
		{
			'WebName' => 'Main',
			'OwnerGroup' => ['ardhi-florida@hw.e-flamingo.net',
		  'ardhi-daikyocho@octops.e-flamingo.net','dejesus.joel@gmail.com'] 
		},
		{
			'WebName' => 'System',
			'OwnerGroup' => ['ardhi-florida@hw.e-flamingo.net',
		  'ardhi-daikyocho@octops.e-flamingo.net','dejesus.joel@gmail.com']
		},
		{
			'WebName' => 'Trash',
			'OwnerGroup' => ['ardhi-florida@hw.e-flamingo.net',
		  'ardhi-daikyocho@octops.e-flamingo.net','dejesus.joel@gmail.com']
		},
		{
			'WebName' => 'SandBox',
			'OwnerGroup' => ['ardhi-florida@hw.e-flamingo.net',
		  'ardhi-daikyocho@octops.e-flamingo.net','dejesus.joel@gmail.com']
		}
	]
};

# Load GPG keys from disk
$siteinput->{'GPG'}->{'dejesus.joel@gmail.com'} = `cat /home/joeldejesus/Workspace/florida1986/joel.asc`;
$siteinput->{'GPG'}->{'ardhi-florida@hw.e-flamingo.net'} = `cat /home/joeldejesus/Workspace/florida1986/florida.asc`;
$siteinput->{'GPG'}->{'ardhi-daikyocho@octops.e-flamingo.net'} = `cat /home/joeldejesus/Workspace/florida1986/daikyocho.asc`;
# Load PP and pairing from disk
$siteinput->{'Sites'}->{'PublicParameters'} = `cat /home/joeldejesus/Workspace/florida1986/PP.blob`;
$siteinput->{'Sites'}->{'pairing'} = `cat /home/joeldejesus/Workspace/florida1986/pairing.blob`;

=pod
---+ Define functions
=cut



sub metakiller {
	my $web = shift;
	my $topic = shift;
	#$wtmapper->{$web}->{$topic} = createUUID();
	#print "($web.$topic:$wtmapper->{$web}->{$topic})\n" if $topic eq 'DefaultPreferences';

	opendir(my $fh, "$dump/$web/Topics/$topic") || "cannot open directory.";
	my @dirs = readdir($fh);
	closedir($fh);
	foreach my $dir (@dirs) {
		next if $dir eq '.' || $dir eq '..' || $dir eq 'Blob_Store';
		my $tablename = $dir;
		if($dir =~ m/(.*)\.[0-9]+$/){
			$tablename = $1;
		}
		#print "$tablename\n";
	}

}



sub createUUID {
	my $ug = new Data::UUID;
	
	my $uuid = $ug->create();		
	return lc($ug->to_string( $uuid ));
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
---++ Define Handlers
=cut

sub blobkeyScan {
	my ($input,$fp,$web,$topic,$name) = @_;
	
	my $blobstoreFP;
	my @tmparray = split('/',$fp);
	$tmparray[-1] = 'Blob_Store';
	$blobstoreFP = join('/',@tmparray);
	die "no blob store ($blobstoreFP)" unless -d "$blobstoreFP" || -f "$blobstoreFP/$name";
	my $y = $input->{'wt'}->{"$web.$topic.TOPICKEY"}; 
	$input->{'wt'}->{"$web.$topic.TOPICKEY"} = createUUID() unless defined $y;
	$y = $input->{'wt'}->{"$web.$topic.TOPICKEY"};
	my $blobvalue = `cat $blobstoreFP/$name`;
	my $xo = Digest::SHA1::sha1_hex($blobvalue);
	#print "Pre(".$input->{'wt'}->{"$web.$topic.TOPICKEY"}.")($blobstoreFP/$name):$xo\n";
	return merkleroot($y,$blobvalue);
}
sub replacer {
	my $input = shift;
	my $fp = shift;
	
	die "no file!($fp)" unless -f "$fp";
	my $tc = `cat $fp`;
	foreach my $line (split("\n",$tc)){
		# do regex
		my $x;
		my $xmod;
		if($line =~ m/([a-zA-Z0-9]+)\.([a-zA-Z0-9]+)\.TOPICKEY/){
			$x = "$1.$2.TOPICKEY";
		}
		elsif($line =~ m/([a-zA-Z0-9]+)\.WEBKEY/){
			$x = "$1.WEBKEY";
		}
		elsif($line =~ m/([a-zA-Z0-9]+)\.([a-zA-Z0-9]+)\.([a-zA-Z0-9_]+)\.BLOBKEY/){
			$x = "$1.$2.$3.BLOBKEY";
			$xmod = encode(blobkeyScan($input,$fp,$1,$2,$3));
		}
		if(defined $x){
			my $y = $input->{'wt'}->{$x};
			$input->{'wt'}->{$x} = createUUID() unless $y;
			$y = $input->{'wt'}->{$x};
			$y = $xmod if $xmod; # replacing BLOBKEY
			# search and replace
			$tc =~ s/$x/$y/g;
		}
		
	}
	open(my $fh, '>',$fp);
	print $fh $tc;
	close $fp;
}

sub sitehandler {
	my $input = shift;
	my $files = {};
	my $fp = $input->{'file_path'};
	

	# copy sites01 to the new site name
	my @SiteArray;
	$input->{'wt'}->{'SITEKEY'} = createUUID();
	$input->{'wt'}->{'Main.WebHome.TOPICKEY'} = createUUID();
	$input->{'wt'}->{'Main.AdminUser.TOPICKEY'} = createUUID();
	$input->{'wt'}->{'Main.WikiGuest.TOPICKEY'} = createUUID();
	$input->{'wt'}->{'Main.AdminGroup.TOPICKEY'} = createUUID();
	$input->{'wt'}->{'System.WEBKEY'} = createUUID();
	$input->{'wt'}->{'Trash.WEBKEY'} = createUUID();
	$input->{'wt'}->{'Main.WEBKEY'} = createUUID();
	$input->{'wt'}->{'Main.SitePreferences.TOPICKEY'} = createUUID();
	$input->{'wt'}->{'System.DefaultPreferences.TOPICKEY'} = createUUID();
	
	push(@SiteArray,$input->{'wt'}->{'SITEKEY'}); # <--SITEKEY
	push(@SiteArray,$input->{'Sites'}->{'SiteName'}); # <--SITENAME
	push(@SiteArray,encode(dhash($input->{'Sites'}->{'PublicParameters'})) ); # <--PP
	push(@SiteArray,$input->{'wt'}->{'Main.WebHome.TOPICKEY'});# <--SITEHOME
	push(@SiteArray,$input->{'wt'}->{'Main.AdminUser.TOPICKEY'} ); # <--ADMINUSER
	push(@SiteArray,$input->{'wt'}->{'Main.WikiGuest.TOPICKEY'}); # <--GUESTUSER
	push(@SiteArray,$input->{'wt'}->{'Main.AdminGroup.TOPICKEY'}); # <--ADMINGROUP
	push(@SiteArray,$input->{'wt'}->{'System.WEBKEY'}); # <--SYSTEMWEB
	push(@SiteArray,$input->{'wt'}->{'Trash.WEBKEY'}); # <--TRASHWEB
	push(@SiteArray,$input->{'wt'}->{'Main.WEBKEY'}); # <--HOMEWEB
	push(@SiteArray,$input->{'wt'}->{'Main.SitePreferences.TOPICKEY'}); # <--LOCALPREFERENCES
	push(@SiteArray,$input->{'wt'}->{'System.DefaultPreferences.TOPICKEY'}); # <--DEFAULTPREFERENCES

	# this is the global counter, to help create fileblob directories
	$COUNT++;
	my $tmp = $COUNT;
	
	mkdir "$fp/$tmp"; # <--create a temporary directory for each fileblob

	# print Sites
	open(my $fh, '>', "$fp/$tmp/Sites");
	print "Printing Sites\n";
	print $fh join("\n",@SiteArray);
	close $fh;

	# print Site_History
	my @SHArray;
	open($fh, '>', "$fp/$tmp/Site_History");
	print "Printing Site History\n";
	push(@SHarray,$input->{'wt'}->{'SITEKEY'});  # <-- SITEKEY
	push(@SHarray,encode(dhash($input->{'GPG'}->{$input->{'Sites'}->{'Owner'}})));  # <-- OWNERKEY	
	my @merkleinput;
	foreach my $x (@{$input->{'Sites'}->{'OwnerGroup'}}){
		push(@merkleinput,$input->{'GPG'}->{$x});
	}
	push(@SHarray,encode(merkleroot(@merkleinput))); # <-- OWNERGROUP
	push(@SHarray,time()); # <-- STARTTIME
	
	# by defualt, owner of topic get all rights (7)
	# ..also, group gets all rights as well (7*(2**3))
	# the default user is the admin user, the default group is the admin group
	push(@SHarray,int(7 + 7*(2**3) )); # <-- PERMISSIONS
	print $fh join("\n",@SHarray);
	close $fh;
	
	# print Site_History.OwnerGroup
	open($fh,'>',"$fp/$tmp/Site_History.OwnerGroup");
	print "Printing Site History Owner Group\n";
	print $fh join("\n",@{$input->{'Sites'}->{'OwnerGroup'}});
	close $fh;
	
	 
	# Public Parameter (not printed anymore, sent directly from wezi to wezi)
	
	# derive the site history key
	
	my $output = Digest::SHA1::sha1_hex(join("\n",@SHarray));
	
	my $uuid;
	if($output =~ m/^([0-9a-f]{8})([0-9a-f]{4})([0-9a-f]{4})([0-9a-f]{4})([0-9a-f]{12})/){
		$uuid = "$1-$2-$3-$4-$5";
	}
	$input->{'wt'}->{'SITEHISTORYKEY'} = $uuid;
	# write down the info file
	open($fh,'>',"$fp/$tmp.info");
	print "Printing info file for site.\n";
	print $fh "$uuid\n"; # <--site history key>
	print $fh "\n"; # <--web history key>
	print $fh ""; # <--topic key>
	close $fh;
	
	
}

sub webhandler {
	my ($input,$element) = @_;
	
	my $web = $element->{'WebName'};
	
	my $fp = $input->{'file_path'};
	my $oldfp = $dump;
	
	$COUNT++;
	my $tmp = $COUNT;
	
	opendir(my $fh, "$dump/$web");
	my @webDIR = readdir($fh);
	closedir($fh);
	
	foreach my $file (@webDIR){
		next if $file eq '.' || $file eq '..' || -d "$dump/$file";
		
		print "$web.$file\n";
	}
	# create directory
	mkdir "$fp/$tmp";
	
	# Webs
	`cp $dump/$web/Webs $fp/$tmp/Webs`;
	replacer($input,"$fp/$tmp/Webs");
	
	# Web_History
	open($fh,'>',"$fp/$tmp/Web_History");
	print "Printing Webs for $web.\n";
	my @WHarray;
	push(@WHarray,$input->{'wt'}->{'SITEHISTORYKEY'}); # <--SITEHISTORYKEY
	push(@WHarray,$input->{'wt'}->{"$web.WEBKEY"}); # <--WEBKEY
	push(@WHarray,time()); # <--STARTTIME
	my @merkleinput;
	foreach my $x (@{$element->{'OwnerGroup'}}){
		push(@merkleinput,$input->{'GPG'}->{$x});
	}
	push(@WHarray,encode(merkleroot(@merkleinput)) );  # <--OWNERGROUP
	push(@WHarray,int(7 + 7*(2**3) ) ); # <-- PERMISSIONS
	print $fh join("\n",@WHarray);
	close $fh;
	# OwnerGroup
	print "Printing Web History OwnerGroup.\n";
	open($fh,'>',"$fp/$tmp/Web_History.OwnerGroup");
	print $fh join("\n",@{$element->{'OwnerGroup'}});
	close $fh;
	
	# info
	print "Printing info\n";
	# derive web history key
	die "no webkey!" unless defined $input->{'wt'}->{"$web.WEBKEY"};
	my $output = Digest::SHA1::sha1_hex(join("\n",@WHarray));
	my $uuid;
	if($output =~ m/([0-9a-f]{8})([0-9a-f]{4})([0-9a-f]{4})([0-9a-f]{4})([0-9a-f]{12})/){
		$uuid = "$1-$2-$3-$4-$5";
	}
	
	print "$web:($uuid|".substr($output,0,32).")\n";
	$input->{'wt'}->{"$web.WEBHISTORYKEY"} = $uuid;

	open($fh,'>',"$fp/$tmp.info");
	print $fh $input->{'wt'}->{'SITEHISTORYKEY'}."\n"; # <-- SITEHISTORYKEY
	print $fh $input->{'wt'}->{"$web.WEBHISTORYKEY"}."\n"; # <-- WEBHISTORYKEY
	print $fh ""; # <-- TOPICKEY
	close $fh;
	
}

sub topichandler {
	my ($input,$web,$topic) = @_;
	#die "No web or topic" unless defined $web && defined $topic;
	my $fp = $input->{'file_path'};
	$COUNT++;
	my $tmp = $COUNT;
	die "No Topic ($dump/$web/Topics/$topic)" unless -d "$dump/$web/Topics/$topic";
	# get the topic key
	#print "H1\n";
	my $topickey = $input->{'wt'}->{"$web.$topic.TOPICKEY"};
	unless (defined $topickey){
		$topickey = createUUID();
		$input->{'wt'}->{"$web.$topic.TOPICKEY"} = $topickey;
	}
	# create fileblob directory
	#print "H2\n";
	`cp -r $dump/$web/Topics/$topic $fp/$tmp`;
	

	#print "H3\n";
	# run search and replace on Blob_Store 
	opendir(my $fh, "$fp/$tmp/Blob_Store");
	my @topicDIR = readdir($fh);
	closedir($fh);
	foreach my $bs (@topicDIR){
		next if $bs eq '.' || $bs eq '..';
		die "why is there a directory here?" unless -f "$fp/$tmp/Blob_Store/$bs";
		replacer($input,"$fp/$tmp/Blob_Store/$bs");
		
		# move Blob.X to proper position
		my $bvalue = `cat $fp/$tmp/Blob_Store/$bs`;
		
		my $blobkey = encode_safe(merkleroot($topickey,$bvalue));
		my $xo = Digest::SHA1::sha1_hex($bvalue);
		#print "Post($topickey)($fp/$tmp/Blob_Store/$bs):$xo\n";
		#`mv $fp/$tmp/Blob_Store/$bs $fp/$tmp/Blob_Store/$blobkey`;
	}	

	#print "H4\n";
	# run search and replace on all files in directory (not blob store yet)
	opendir($fh, "$fp/$tmp");
	@topicDIR = readdir($fh);
	closedir($fh);
	foreach my $bs (@topicDIR){
		next if $bs eq '.' || $bs eq '..' || -d "$fp/$tmp/$bs";
		replacer($input,"$fp/$tmp/$bs");
	}
	# create info file
	open($fh,'>',"$fp/$tmp.info");
	print $fh $input->{'wt'}->{'SITEHISTORYKEY'}."\n"; # <--SITEHISTORYKEY
	print $fh $input->{'wt'}->{"$web.WEBHISTORYKEY"}."\n"; # <--WEBHISTORYKEY
	print $fh $input->{'wt'}->{"$web.$topic.TOPICKEY"}; # <--TOPICKEY
	close($fh);

	# extra
	_adminuser($input,$web,$topic,"$fp/$tmp") if "$web.$topic" eq 'Main.AdminUser';

	return 0;
}

sub _adminuser {
	my ($input,$web,$topic,$dir) = @_;
	
	# change the User_History to reflect the owner of the new Site
	open(my $fh,'>',"$dir/User_History");
	print $fh $input->{'Main.Admin'}->{'first_name'}."\n"; # FIRSTNAMEPUTHERE
	print $fh $input->{'Main.Admin'}->{'last_name'}."\n"; # LASTNAMEPUTHERE
	
	print $fh encode(merkleroot(
		$input->{'wt'}->{'SITEKEY'},
		$input->{'wt'}->{"$web.$topic.TOPICKEY"},
		$input->{'Main.Admin'}->{'password'}
	))."\n"; # PASSWORDPUTHERE
	print $fh $input->{'Main.Admin'}->{'email'}."\n"; # EMAILPUTHERE
	print $fh $input->{'Main.Admin'}->{'country'}."\n"; # COUNTRYPUTHERE
	print $fh $input->{'Main.Admin'}->{'callback_number'}."\n"; # CALLBACKNUMBERPUTHERE
	print $fh $input->{'Main.Admin'}->{'gpgkey'}."\n"; # GPGKEYPUTHERE
	close($fh);
	
	# do a search and replace of Users (admin->loginnameOfActualPerson)
	open($fh,'<',"$dir/Users");
	my $userstxt = join('',<$fh>);
	close($fh);
	my $loginname = $input->{'Main.Admin'}->{'loginname'};
	$userstxt =~ s/admin/$loginname/g;
	open($fh,'>',"$dir/Users");
	print $fh $userstxt;
	close($fh);	
}
=pod
---+ Main Program
=cut

sub cycler{
	my $input = shift;
	opendir(my $fh1, $dump) || die "no directory.";
	my @dirs = readdir($fh1);
	closedir $fh1;
	
	foreach my $web (@dirs){
		next unless -d "$dump/$web";
		next if $web eq '.' || $web eq '..';
		my @sr1 = @{$input->{'Webs'}};
		my $element;
		foreach my $er1 (@sr1){
			$element = $er1 if $er1->{'WebName'} eq $web;
			last if $er1->{'WebName'} eq $web;
		}
		die "No Web" unless $element;
		webhandler($input,$element);
		opendir(my $fh2, "$dump/$web/Topics") || die "no directory.";
		my @dirs1 = readdir($fh2);
		foreach my $topic (@dirs1){
			next if $topic eq '.' || $topic eq '..';
			#metakiller($web,$topic);
			topichandler($input,$web,$topic);
		}
		closedir $fh2;
	}
}
# step 1
# ..copy sites01
my $sname = $siteinput->{'Sites'}->{'SiteName'};
die "No Site Name" unless $sname;
my $oldsite = '/home/joeldejesus/Workspace/foswiki-main/core/data/sites01';
my $newsite = "/tmp/wiki/$sname";
$siteinput->{'file_path'} = $newsite;
if(-d $newsite){
	# delete
	`rm -r $newsite`;
}
mkdir $newsite;
#`cp -r $oldsite $newsite`;

# attach the web.topic name mapper to $siteinput
$siteinput->{'wt'} = $wtmapper;
sitehandler($siteinput);
cycler($siteinput);
1;

__END__
