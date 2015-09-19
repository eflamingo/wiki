# perl

my $base = '/home/joeldejesus/Workspace/foswiki-main/core/data/sites01';

sub TH;

opendir(my $fh, $base);
my @webs = readdir($fh);
closedir($fh);


foreach my $web (@webs){
	next if $web eq '.' || $web eq '..' || -f "$base/$web";
	#print "$web\n";
	opendir($fh,"$base/$web/Topics");
	my @topics = readdir($fh);
	closedir($fh);
	foreach my $topic (@topics){
		next if $topic eq '.' || $topic eq '..' || -f "$base/$web/Topics/$topic";
		#print "($web,$topic)\n";
		TH($web,$topic);
	}
}

sub TH {
	my ($web,$topic) = @_;
	my $fp = "$base/$web/Topics/$topic/Topic_History";
	open(my $fh, '<',$fp);
	my $counter = 0;
	my $topickey = "";
	while(my $line = <$fh>){
		if($line =~ m/([a-zA-Z0-9]*)\.([a-zA-Z0-9]*)\.TOPICKEY/){
			$topickey = "$1.$2.TOPICKEY"; 
		}
	}
	close($fh);
	my $time = time();
	my $permission = (1*(2**0)+1*(2**1)+1*(2**2))+
		(2**3)*(1*(2**0)+1*(2**1)+1*(2**2))+
		(2**6)*(1*(2**0)+0*(2**1)+0*(2**2)); # u->rwx;g->rwx;o->r--
	my $text = qq{$web.$topic.TOPICKEY
Main.AdminUser.TOPICKEY
$web.WEBKEY
$time
$web.$topic.topic_content.BLOBKEY
$web.$topic.topic_name.BLOBKEY
Main.AdminUser.TOPICKEY
Main.AdminGroup.TOPICKEY
$permission};
	open($fh,'>',$fp);
	print $fh $text;
	close($fh);
}

=pod
  key uuid NOT NULL,
  topic_key uuid NOT NULL,
  user_key uuid NOT NULL,
  web_key uuid NOT NULL,
  timestamp_epoch integer NOT NULL,
  topic_content bytea NOT NULL,
  topic_name bytea NOT NULL,
  owner
  permissions
=cut
