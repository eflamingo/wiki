# See bottom of file for license and copyright information


package Foswiki::Contrib::DBIStoreContrib::AmazonS3;


use MIME::Base64 qw(decode_base64 encode_base64);
use Net::Amazon::S3 ();
use Crypt::PBC;
use Digest::SHA1 qw(sha1);
use Crypt::CBC;
use Crypt::Blowfish;
use  Compress::Zlib();


my $bucket_cache;
my $s3_cache;
my $GENERATOR;
my $SECRET;
my $PUBLICKEY;
my $PAIRING;


=pod
---+ new 
   * create new object   
   *->new()

=cut

sub new {
	my $class = shift;
	my $this;
	my $site_key = shift;
	return undef unless $site_key;
	$this->{site_key} = $site_key;
	bless $this,$class;

	return $class;
}

sub site_key {
	my $this = shift;
	return $this->{site_key};
}
#.............. encryption related functions when initiating new object .............
sub pairing {
	my $this = shift;
	return $PAIRING if $PAIRING;
	$PAIRING = Crypt::PBC::pairing_init_str($Foswiki::cfg{Store}{DBI}{s3_parameters});
	return $PAIRING;
}

sub generator {
	my $this = shift;
	return $GENERATOR if $GENERATOR;
	$GENERATOR = $this->pairing->init_G2->set_to_bytes(decode_base64($Foswiki::cfg{Store}{DBI}{s3_generator}));
	return $GENERATOR;
}

sub secret {
	my $this = shift;
	return $SECRET if $SECRET;
	$SECRET = $this->pairing->init_Zr->set_to_bytes(decode_base64($Foswiki::cfg{Store}{DBI}{s3_secret}));
	return $SECRET;
}

sub master_public_key {
	my $this = shift;
	return $PUBLICKEY if $PUBLICKEY;
	$PUBLICKEY = $this->pairing->init_G2->set_to_bytes(decode_base64($Foswiki::cfg{Store}{DBI}{s3_public_key}));
	return $PUBLICKEY;
}
#.............. amazon s3 related functions .............

sub s3 {
	my $this = shift;
	return $s3_cache if $s3_cache;
        $s3_cache = Net::Amazon::S3::->new(
                aws_access_key_id     => $Foswiki::cfg{Store}{DBI}{amazon_id},
                aws_secret_access_key => $Foswiki::cfg{Store}{DBI}{amazon_key},
                retry                 => 1,
        );
	return $s3_cache;
}
# ($site_key)->$bucket Object corresponding to a particular site
sub bucket {
	my $this = shift;
	return $this->{_bucket};
}
=pod
---+ save_keyvalue
($site_key,$key,$value)-> compress, encrypt, send to amazon
We need the $site_key so we know which amazon s3 bucket we are working with

This function feeds from Handler::add_key
=cut
sub save_keyvalue {
	my $this = shift;
	my $key = shift;
	my $value = shift;
	# get the s3 bucket corresponding to this site
	# setup the proper bucket
	my $site_key = shift;
	my $s3 = $this->s3;
	my $bucket = $s3->bucket('e-flamingo-wikidb-'.$site_key);
	die "no bucket ($bucket,$site_key)" unless $bucket && $site_key;

	# 1. we need to derive a point in G1 as Qid (the public key)
	my $Q_i  = $this->pairing->init_G1->set_to_hash( sha1($key) );
	# 2. set g_id = e_hat(Qid,P_pub)
	my $g_i = $this->pairing->init_GT->e_hat( $Q_i, $this->master_public_key );
	# 3. generate a random r set of Integers Mod (some really big number listed in the parameters)
	my $r   = $this->pairing->init_Zr->random;
	# 4. multiply*
	my $rP  = $this->pairing->init_G2->pow_zn( $this->generator, $r );
	# 5. take Number 3. to the Rth power
	my $W1  = $g_i->clone->pow_zn( $r );


	# Compress the $value part before encrypting
	my $CompressedFile = Compress::Zlib::memGzip($value)  or die "Cannot compress $gzerrno\n";

	my $C1 = new Crypt::CBC({header=>'randomiv', key=>$W1->as_bytes, cipher=>"Blowfish"});
	# do a buffer for blowfish
	
	my $done_size = 0;
	my $total_size = length($CompressedFile);
	my $BufferSize = 8192;
	my $enc_data;
	$C1->start('encrypting');
	while($done_size < $total_size){		
		my $subX = substr($CompressedFile,$done_size,$BufferSize);
		$enc_data .= $C1->crypt($subX);
		$done_size += $BufferSize;
	}
	$enc_data .= $C1->finish();
	my @m  = ($rP->as_base64, $enc_data);
	# get rid of this to save memory
	undef $CompressedFile;
	undef $Q_i;
	undef $C1;
	undef $g_i;
	undef $r;
	undef $rP; 
	undef $W1;
	
	# Now we have C = {U,V}
	# upload the U
	$bucket->add_key( $key.'--+U' , $m[0],
		{ content_type => 'text/html', },
	   ) or die $this->s3->err . ": " . $this->s3->errstr;
	# upload the V
	$bucket->add_key( $key, $m[1],
		{ content_type => 'application/z-gzip', },
	   ) or die $this->s3->err . ": " . $this->s3->errstr;	
	# success?
	return 1;
}
=pod
---+ fetch_keyvalue
($site_key,$key,$value)-> compress, encrypt, send to amazon
We need the $site_key so we know which amazon s3 bucket we are working with

This function feeds from Handler::add_key
=cut
sub fetch_keyvalue {
	my $this = shift;
	my $key = shift;

	# get the s3 bucket corresponding to this site
	# setup the proper bucket
	my $site_key = shift;
	my $s3 = $this->s3;
	my $bucket = $s3->bucket('e-flamingo-wikidb-'.$site_key);
	die "no bucket ($bucket,$site_key)" unless $bucket && $site_key;


	# fetch U
	my $respU = $bucket->get_key($key.'--+U') or die $s3->err . "($key,$site_key): " . $s3->errstr;
	my $uBin = decode_base64($respU->{value});
	my $uG2 = $this->pairing->init_G2->set_to_bytes($uBin);

	my $respV = $bucket->get_key($key)  or die $s3->err . "($key): " . $s3->errstr;
	my $vBin = $respV->{value};

	die "failed to get files" unless length($uG2) > 0 && length($vBin) > 0;


	# 1. we need to derive a point in G1 as Qid (the public key)
	my $Q_i = $this->pairing->init_G1->set_to_hash( sha1($key) );
	# 2. using the master secret, find the private key for this attachment
	my $s_i = $this->pairing->init_G1->pow_zn($Q_i,$this->secret);
	
	
	my $W2 = $this->pairing->init_GT->e_hat( $s_i, $uG2 );
	my $C2  = new Crypt::CBC({
		header=>"randomiv" 
		,key=>$W2->as_bytes 
		,cipher=>"Blowfish"
#		,insecure_legacy_decrypt => 1
	});


	# let's decrypt in 8192Byte chunks

	$C2->start('decrypting');
	my $done_size = 0;
	my $total_size = length($vBin);
	my $BufferSize = 8192;
	while($done_size < $total_size){
		my $subX = substr($vBin,$done_size,$BufferSize);
		$plaindata .= $C2->crypt($subX);
		$done_size += $BufferSize;
	}
	# CAREFUL! .= vs =  , should be .= !
	$plaindata .= $C2->finish();



	

	die "no file (".$W2->as_base64.") " unless length($plaindata) > 0;
	# get rid of variables that are no longer needed	
	undef $Q_i;
	undef $s_i;
	undef $W2;
	undef $C2;
	undef $uBin;
	undef $vBin;
	undef $uG2;


	# Compress the $value part before encrypting
	# http://perldoc.perl.org/Compress/Zlib.html

	my $deCompressedFile = Compress::Zlib::memGunzip($plaindata) or die "Cannot uncompress: $gzerrno\n";
	#die "inside:".length($deCompressedFile)." and ".length($plaindata);
	undef $plaindata;
	#die "e".length($deCompressedFile)." w(".$uG2->as_base64." =? ".$respU->{value}."):".length($plaindata)."  r:".length($vBin)."  d:".$respV->{content_length};
	# success?

	return $deCompressedFile;
}


=pod
---+ load 
   * load existing object
   *->load($key,$topic_history_key)
=cut
sub load {
	my $class = shift;

	my $this;
=pod
	$this->{key} = shift;
	$this->{history_key} = shift;
	bless $this,$class;
	# load the bucket and
	# load the s3::object
	$this->_object($this->s3bucket->object(key=>$this->key) );
	$this->value($this->_object->get);
=cut
	return $this;
}






sub key64 {
	my $this = shift;
	return undef unless $this->{key};
	return $this->{key64} if $this->{key64};
	# convert binary sha1 key to base 64
	$this->{key64} = MIME::Base64::encode_base64($this->{key});
	return $this->{key64};
}
sub key {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{key} = $x;
		return $this->{key};
	}
	else{
		return $this->{key};
	}
}

sub value {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{value} = $x;
		return $this->{value};
	}
	else{
		return $this->{value};
	}
}

sub _object {
        my $this = shift;
        my $x = shift;
        if($x){
                $this->{_object} = $x;
                return $this->{_object};
        }
        else{
                return $this->{_object};
        }
}



sub public_id {
	my $this = shift;
	my $site_key = $this->{site_key};
	if($site_key){
		return $site_key.$this->{topic_history_key};
	}
	else{
		return 'naked'.$this->{topic_history_key};
	}
}

sub private_key {
        my $this = shift;
        return $this->{private_key} if $this->{private_key};
	# if there is no private key, we have to ask the key server to produce one for us
	#...
}




1;

__END__

