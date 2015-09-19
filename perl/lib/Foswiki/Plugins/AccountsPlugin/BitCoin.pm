package Foswiki::Plugins::AccountsPlugin::BitCoin;

use strict;
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64 );
use Digest::SHA qw(hmac_sha1_hex);

# create a new BitCoin Object (a bitcoin object represents only 1 order)
sub new {
	my $class = shift;
	my $order_obj = shift;	
	my $this;
	
	$this->{order} = $order_obj;
		
	bless $this, $class;
	
	return $this;
}
=pod
---+ Getters and Setters

=cut

sub order {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{order} = $x;
		return $this->{order};
	}
	else{
		return $this->{order};
	}
}

sub order_id {
	my $this = shift;
	return $this->order->key;
}


sub timestamp_epoch {
	my $this = shift;
	return $this->order->post_date;
}

sub address {
	my $this = shift;
	# make sure we did not already find the address
	return $this->{address} if $this->{address};
	
	# from now on, assuming no address exists for this bitcoin object
	my $address = '';
	my $order_id = $this->order->key;
	my $order_obj = $this->order;
	my $handler = $order_obj->handler;
	
	# check if this order already exists or not
	my $is_old = $order_obj->_previously_loaded();
	my $bita = $handler->getTableName('BitCoinAddresses');
	my ($selectStatement,$selectHandler);
	if(!$is_old){
		# fetch the bitcoin address from the database which does not have an order_id
		$selectStatement = qq/
SELECT
 ba.address, ba.balance
FROM
  $bita ba
WHERE 
  ba.order_id IS NULL
LIMIT 1/;
		$selectHandler = $handler->database_connection()->prepare($selectStatement);
		$selectHandler->execute();
		
		# we have to mark this bitcoin address as belonging to this address in the database
		# let's do it at the end of this function
	}
	else{
		# fetch bitcoin address that matches this order
		$selectStatement = qq/
SELECT
 ba.address, ba.balance
FROM
  $bita ba
WHERE 
  ba.order_id = ? /; # 1-order_id
		$selectHandler = $handler->database_connection()->prepare($selectStatement);
		$selectHandler->execute($order_id);
	}
	my ($address,$balance);
	$selectHandler->bind_col( 1, \$address );
	$selectHandler->bind_col( 2, \$balance );
	my $answer_hash;
	while ($selectHandler->fetch) {
		# we should only be getting one result
		$answer_hash->{'balance'} = $balance;
		$answer_hash->{'address'} = $address;
	}
	$this->{address} = $address;
	$this->{balance} = $balance;
	
	# we have to mark this bitcoin address as belonging to this address in the database
	$this->_save_address if !$is_old;	
	
	return $address;
}

sub balance {
	my $this = shift;
	# check if the balance already exists
	return $this->{balance} if $this->{balance};
	# else, fetch the balance along with the address
	$this->address;
	return $this->balance;
}


# has an eval inside, writes to database!
# don't run this function independently of the $this->address function
# INTERNAL USE ONLY!
sub _save_address {
	my $this = shift;
	my $order_obj = $this->order;
	my $handler = $this->order->handler;
	my $bita = $handler->getTableName('BitCoinAddresses');
	my $update_statement = qq/
UPDATE $bita
SET
 order_id = ?
WHERE 
  address = ? /; # 1-order_id, 2-address;
	my $update_handler = $handler->database_connection()->prepare($update_statement);
	
	# do an update on the bitcoin address table
	$handler->database_connection()->{AutoCommit} = 0;
	eval{
		# defer constraints
		$handler->set_to_deferred();
		
		$update_handler->execute($order_obj->key,$this->{address});# warning, NEVER USE $this->address... leads to infinite loop!
		
		$handler->database_connection()->commit;
	};
	if ($@) {
		$handler->database_connection()->errstr;
		eval{
			$handler->database_connection()->rollback;
		};
		throw Foswiki::OopsException(
                'attention',
                def    => 'Not Bitcoin Address Added',
                params => ['order_credit']
		);
		
	}
}

1;