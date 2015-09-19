# perl
use MIME::Base64 ();
#use MIME::Base16 ();
use Digest::SHA ();

#my $dir = '/home/joeldejesus/Workspace/foswiki-main/core/data/sites01/Main/Topics/AdminGroup';
my $dir = $ARGV[0];
die "no directory or file" unless -f $dir || -d $dir;
my $web = 'Main';
my $fileblobhash = {};

sub dhash {
	my $x = shift;
	die "No content to sha256\n" unless defined $x && $x ne '';
	return Digest::SHA::sha256(Digest::SHA::sha256($x));
}

=pod
---+ directoryScoop
Take in the directory filepath.
=cut
sub directoryScoop {
	my $directory = shift;
	opendir( my $fh, $directory) || warn "can't open directory\n";
	my @X1 = readdir($fh);
	closedir($fh);
	foreach my $x (@X1){
		next if $x eq '.' || $x eq '..';
		if(-f "$directory/$x"){
			fileScoop("$directory/$x");
		}
		elsif(-d "$directory/$x"){
			#print "Directory($x)\n";
			directoryScoop("$directory/$x");
		}
	}

}

sub fileScoop($fp){
	my $fp = shift;
	my $output = `cat $fp`;
	
	my $relativeFP = $fp;
	$relativeFP =~ s/$dir\///g;
	my @relativeDIR = split('/',$relativeFP);

	$fileblobhash->{$relativeFP} = dhash($output);

	#print "File:$fp\n";
	#die "$fp has no data\n" unless $output ne '';
	#my $y = dhash($output);
	#$y = MIME::Base64::encode_base64($y);
	#print "file($fp:$y)\n";
}

sub printFileBlobHash {
	my $hash = shift;
	my $output = "";
	foreach my $key (sort keys %$hash){
		#my $value = $hash->{$key};
		#print ref($value)."\n";
		#next;
		if ( ref($hash->{$key}) eq 'HASH') {
			#print "Hash Reference:$key\n";
			$output .= printFileBlobHash($hash->{$key});
		}
		else{
			# assuming ref is a SCALAR reference
			#print "Scalar:$hash->{$key}\n";
			$output .= $hash->{$key};
		}
	}
	return $output;
}

directoryScoop($dir);

#require Data::Dumper;
#my $oo = Data::Dumper::Dumper($fileblobhash);
#print "$oo\n\n";

print dhash(printFileBlobHash($fileblobhash));
