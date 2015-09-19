package Foswiki::Plugins::AccountsPlugin::Contracts;

use strict;
use Foswiki::UI::Accounts();
use Foswiki::Plugins::AccountsPlugin::Products();

# create a new Contract Object (only represents 1 order)
sub new {
	my $class = shift;
	my $key = shift;	
	my $this;
	$this->{key} = $key;
	unless($this->{key}){
		# create a new key if none is provided
		require Foswiki::Contrib::DBIStoreContrib::Handler;
		my $handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
		$this->{key} = $handler->createUUID();	
	}
	
	bless $this, $class;
	
	$this->term(-1);
	$this->start(-1);
	$this->end(-1);

	return $this;
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

sub owner {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{owner} = $x;
		return $this->{owner};
	}
	else{
		return $this->{owner};
	}
}

sub term {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{term} = $x;
		return $this->{term};
	}
	else{
		return $this->{term};
	}
}

sub start {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{start} = $x;
		return $this->{start};
	}
	else{
		return $this->{start};
	}
}

sub end {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{end} = $x;
		return $this->{end};
	}
	else{
		return $this->{end};
	}
}
# contract topic => type
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

# this is for handling databases
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

sub _previously_loaded {
	my $this = shift;
	my $x = shift;
	if($x){
		$this->{_previously_loaded} = $x;
		return $this->{_previously_loaded};
	}
	else{
		return $this->{_previously_loaded};
	}
}

#######################################################


###########   db interaction functions  ###########
sub save{
	my $this = shift;
	if($this->_previously_loaded == 1){
		# old contract from old order
		return $this->update_contract;
	}
	else{
		# new contract from new order
		return $this->save_new_contract;
	}
}


sub save_new_contract {
	my $this = shift;
	return undef unless $this->handler;
	
	my $handler = $this->handler;
	$this->key($handler->createUUID());
	
	my $Contracts = $handler->getTableName('Contracts');	
	my $insertStatement = qq/ INSERT INTO $Contracts (contract_id, term, start_date, end_date, type_of_contract, owner_key) VALUES (?,?,?,?,?,?); 	/;
	my $insertHandler = $handler->database_connection()->prepare($insertStatement);
	$insertHandler->execute($this->key,$this->term,$this->start,$this->end,$this->type,$this->owner);
	return $this->key;
}
# should only be called from Order object
sub update_contract {
	my $this = shift;
	my $new_start_date = $this->start;
	my $handler = $this->handler;
	# update the Contract Table
	my $Contracts = $handler->getTableName('Contracts');
	my $updateStatement = qq/
  UPDATE $Contracts
  SET start_date = ?, end_date = ?
  WHERE contract_id = ? ; 
  /; # 1-start_date, 2-end_date, 3-contract_id
	my $updateHandler = $handler->database_connection()->prepare($updateStatement);
	my $end_date = $this->_calculate_End_Date($new_start_date);
	$updateHandler->execute($new_start_date,$end_date,$this->key);
}

#######################################################

sub _calculate_End_Date {
	my ($this,$new_start_date) = @_;
	my $term = $this->term; 
=pod
http://answers.yahoo.com/question/index?qid=20080904102842AAuCDvw

Depends if the month has 29, 30, or 31 days, you can take an average by calculating for a year and dividing by 12

60sec/min, 60min/hour, 24hr/day, 365days/year, 1year/12months
(60*60*24*365)/12 => 2,628,000
=cut
	my $seconds_per_month = 2628000;
	my $end_date = $term*$seconds_per_month+$new_start_date;
	$end_date = -1 unless $term > 2; # no reason to pick 2. (only means term has to be more than 2 seconds) 
	return $end_date;
}

1;
__END__


E-F owns: Main.ContractEFlamingoOwner20110720

Customer owns: Main.ContractTransferOfOwnerShip20110720

