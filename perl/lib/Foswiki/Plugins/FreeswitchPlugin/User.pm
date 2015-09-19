package Foswiki::Plugins::FreeswitchPlugin::User;

use strict;
use warnings;


use Assert;
use Foswiki::Plugins::FreeswitchPlugin::Handler ();
# let us define some response xml


# new($login_name)->$responsexml for domain section
sub new {
	my $class = shift;
	my $login_name = shift;
	my $this;
		
	$this->{login_name} = $login_name;
	$this->{variables} = {};
	$this->{parameters} = {};
	bless $this, $class;
	return $this;
}
sub login_name {
	my $this = shift;
	return $this->{login_name};
}

sub setVariable {
	my $this = shift;
	my ($name,$value) = @_;
	$this->{variables}->{$name} = $value;
}
sub setParameter {
	my $this = shift;
	my ($name,$value) = @_;
	$this->{parameters}->{$name} = $value;
}
sub getVariable {
	my $this = shift;
	my $name = shift;
	return $this->{variables}->{$name};
}
sub getParameter {
	my $this = shift;
	my $name = shift;
	return $this->{parameters}->{$name};
}

sub setUserPrefs {
	my $this = shift;
	my $pref_key = shift;
	$this->{user_preferences} = $pref_key;
}

##########################    Printing Functions     #################################
sub _print_params {
	my $this = shift;
	my @params = keys %{$this->{parameters}};
	my $return_string = '';
	my @paramXML;
	foreach my $name (@params) {
		push(@paramXML, '<param name="'.$name.'" value="'.$this->getParameter($name).'"/>') if $this->getParameter($name);
	}
	unless(scalar(@paramXML) == 0){
		$return_string = join(' ',@paramXML);
		$return_string = '<params>'.$return_string.'</params>';
	}
	return $return_string;
}
sub _print_vars {
	my $this = shift;
	my @variables = keys %{$this->{variables}};
	my $return_string = '';
	my @varXML;
	foreach my $name (@variables) {
		push(@varXML, '<variable name="'.$name.'" value="'.$this->getVariable($name).'"/>') if $this->getVariable($name);
	}
	unless(scalar(@varXML) == 0) {
		$return_string = join(' ',@varXML);
		$return_string = '<variables>'.$return_string.'</variables>';	
	}
	
	return $return_string;
}
# prints xml for 1 user
sub print_user {
	my $this = shift;
	my $return_string = '';
	
	my $params = $this->_print_params();
	my $vars = $this->_print_vars();
	$return_string = $params.' '.$vars;
	$return_string = '<user id="'.$this->{login_name}.'">'.$return_string.'</user>';
	return $return_string;
}

1;
__END__