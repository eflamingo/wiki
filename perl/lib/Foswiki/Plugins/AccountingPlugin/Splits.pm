package Foswiki::Plugins::AccountingPlugin::Splits;

use strict;
use Foswiki::Func();
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);
use Foswiki::UI::Accounting();

my $keyhash = {
	'site_key' => {},
	'topics' => {},
	'webs' => {},
};

# create a new Split for a new Transaction
sub new {
	my $class = shift;
	my $this;
	$this->{'account'} = '';
	$this->{'amount'} = '';
	bless $this, $class;

	return $this;
}

sub account {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'account'} = $x;
		return $x;
	}
	else{
		return $this->{'account'};
	}
}

sub handler {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'handler'} = $x;
		return $x;
	}
	else{
		return $this->{'handler'};
	}
}

sub key {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'key'} = $x;
		return $x;
	}
	else{
		return $this->{'key'};
	}
}

# negative amount implies debit, positive implies credit
sub amount {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'amount'} = $x;
		return $x;
	}
	else{
		return $this->{'amount'};
	}		
}
sub transaction_key {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{'transaction_key'} = $x;
		return $x;
	}
	else{
		return $this->{'transaction_key'};
	}		
}
# 1-tx_key, 2-account_key, 3-amount
sub generate_key {
	my $this = shift;
	my $tx_key = shift;
	$this->transaction_key($tx_key);
	return undef unless $tx_key;
	$this->key( substr(sha1_hex( $this->transaction_key, $this->account, $this->amount ), 0, - 8) );
	return $this->key;
}

sub save {
	my $this = shift;
	my ($key, $tx_key,$acc,$amt) = ($this->key,$this->transaction_key,$this->account,$this->amount);
	#return undef unless $key && $tx_key && $acc && $amt;
	die "Split($key, $tx_key,$acc,$amt)" unless $key && $tx_key && $acc && $amt;
	my $Splits = Foswiki::UI::Accounting::getTable('Splits');
	my $insert_statement = qq/INSERT INTO $Splits ("key", transaction_key, accounts_key, amount)
VALUES (?, ?, ?, ?)/;
	my $handler = $this->handler;

	my $insert_handler = $handler->database_connection()->prepare($insert_statement);
	$insert_handler->execute($key, $tx_key,$acc,$amt);
	return $key;
}


1;
__END__