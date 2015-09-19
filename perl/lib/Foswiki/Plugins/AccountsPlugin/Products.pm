package Foswiki::Plugins::AccountsPlugin::Products;

use strict;

use Foswiki::UI::Accounts();
use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);
############ Constructors #########################
# this is to create a brand new product not in inventory
sub create_new_product_id {
	my $class = shift;
	my $input = shift;
	my $this = {};
	bless $this, $class;
	
	$this->handler($input->{'handler'});
	$this->contract($input->{'contract'});
	$this->type(  Foswiki::UI::Accounts::getProductType($input->{'product_type'})  );
	$this->timestamp($input->{'contract'}->start);
	
	return $this;
}
# create a new Product Object (only represents 1 order)
sub new {
	my $class = shift;
	my $key = shift;	
	my $this;
	$this->{key} = $key;
	
	bless $this, $class;

	return $this;
}
sub load_ef_default_contract {
	my $this = shift;
	require Foswiki::Plugins::AccountsPlugin::Contracts;
	my $efcontract = Foswiki::Plugins::AccountsPlugin::Contracts::->new();
	
}
###########   variable setters and getters  ###########

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

sub type {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{type} = $x;
		return $this->{type};
	}
	else{
		return $this->{type};
	}
}
sub contract {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{contract} = $x;
		return $this->{contract};
	}
	else{
		return $this->{contract};
	}
}

sub owner {
	my $this = shift;
	return $this->contract->owner;
}

sub handler {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{handler} = $x;
		return $this->{handler};
	}
	else{
		return $this->{handler};
	}
}

sub timestamp {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{timestamp} = $x;
		return $this->{timestamp};
	}
	else{
		return $this->{timestamp};
	}
}
###########   db interaction functions  ###########

sub save {
	my $this = shift;
	return undef unless $this->handler;
	my $handler = $this->handler;

	$this->key($handler->createUUID());

	my $PC = $handler->getTableName('Product_Catalog');
	my $PO = $handler->getTableName('Product_Owner');
	
	# insert product_catalog row
	my $insertStatement = qq/
  INSERT INTO $PO ("key", product_id, contract_id, timestamp_epoch)
VALUES (?,?,?,?);
	/;
	my $insertHandler = $handler->database_connection()->prepare($insertStatement);
	$insertHandler->execute($this->_createProductOwnerKey,$this->key,$this->contract->key, $this->contract->start);
	# insert product_owner row
	$insertStatement = qq/
  INSERT INTO $PC (  product_id, product_type)
VALUES (?,?);
	/;
	$insertHandler = $handler->database_connection()->prepare($insertStatement);
	$insertHandler->execute($this->key,$this->type);
	# blah
	return $this->key;
}

#######################################################

sub _createProductOwnerKey {
	my $this = shift;
	my $key = $this->key;
	# 1-product_id, 2-contract_id, 3-timestamp_epoch
	return substr(sha1_hex($key,$this->contract->key, $this->contract->start ), 0, - 8);

}


1;
__END__
  product_id uuid NOT NULL,
  product_type character varying NOT NULL,
finding products without owners

SELECT 
  pc1.product_id,
  pc1.product_type 
FROM 
  accounts."Product_Catalog" pc1 LEFT JOIN accounts."Product_Owner" po1 ON pc1.product_id = po1.product_id;
