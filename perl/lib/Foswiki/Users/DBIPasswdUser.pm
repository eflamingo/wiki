

package Foswiki::Users::DBIPasswdUser;

use strict;
use warnings;

use Foswiki::Users::Password ();
our @ISA = ('Foswiki::Users::Password');

use Assert;
use Error qw( :try );
use Fcntl qw( :DEFAULT :flock );
use Foswiki::Plugins ();
use Foswiki::ListIterator ();
use Foswiki::Contrib::DBIStoreContrib::UserHandler ();

=pod TML

---++ ClassMethod new( $session ) -> $object

Constructs a new password handler of this type, referring to $session
for any required Foswiki services.

=cut

sub new {
	my ( $class,$session ) = @_;
	my $this = $class->SUPER::new($session);

	# find out what the site key is for future reference
	$this->{site_handler} = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	bless $this, $class;
	return $this;
}


=pod TML

---++ ObjectMethod finish()
Break circular references.

=cut

# Note to developers; please undef *all* fields in the object explicitly,
# whether they are references or not. That way this method is "golden
# documentation" of the live fields in the object.
sub finish {
	my $this = shift;
	bless $this->{site_handler}, *Foswiki::Contrib::DBIStoreContrib::Handler;
	#undef $this->{user_handler};
	$this->SUPER::finish();
	return 1;
}


=pod

=pod TML

---++ ObjectMethod error() -> $string

Return any error raised by the last method call, or undef if the last
method call succeeded.

=cut

sub error {
	my $this = shift;

	return $this->{error};
}


=pod 

---++++ fetchPass($login) -> $passwd

this method is used most of the time to detect if a given
login user is known to the database. the concrete (encrypted) password 
is of no interest: so better use userExists() for that

=cut

sub fetchPass {
	my ($this, $login_name) = @_;
	die "Fetchpass()\n";
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $passwdE = $user_handler->fetchPassWithLoginName($login_name); # returns the cipher text of password
	return $passwdE;
}




=pod 

---++++ checkPassword($login, $password) -> $boolean


Finds if the password is valid for the given user.

Returns 1 on success, undef on failure.

=cut

sub checkPassword {
	my ($this, $login_name, $passU) = @_;
	
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $boolean = $user_handler->checkPasswordByLoginName($login_name,$passU);

	return 1 if $boolean && $boolean != 0;
}

=pod 

---++++ readOnly() -> $boolean

we can change passwords, so return false

=cut

sub readOnly {
  my $this = shift;
  $this->{session}->enterContext('passwords_modifyable');
  return 0;
}

=pod

---++++ isManagingEmails() -> $boolean

we are managing emails, but don't allow setting emails. alas the
core does not distinguish this case, e.g. by using readOnly()

=cut

sub isManagingEmails {
  return 0;
}

=pod 

---++++ getEmails($user_key) -> @emails

emails might be stored in the ldap account as well if
the record is of type possixAccount and inetOrgPerson.
if this is not the case we fallback to twiki's default behavior

=cut

sub getEmails {
	my ($this, $user_key) = @_;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $emailstring = $user_handler->getEmailsWithUserKey($user_key);
	# return the first email....
	return $emailstring;
}

=pod TML

---++ ObjectMethod removeUser( $login ) -> $boolean

Delete the users entry.

=cut


sub removeUser {
	my $this = shift;

	return $this->{secondaryPasswordManager}->removeUser(@_)
		if $this->{secondaryPasswordManager};

	$this->{error} = 'System does not support removing users';
	return undef;
}

=pod TML

---++ encrypt( $login, $passwordU, $fresh ) -> $passwordE

Will return an encrypted password. Repeated calls
to encrypt with the same login/passU will return the same passE.

However if the passU is changed, and subsequently changed _back_
to the old login/passU pair, then the old passE is no longer valid.

If $fresh is true, then a new password not based on any pre-existing
salt will be used. Set this if you are generating a completely
new password.

=cut

sub encrypt {
    return '';
}
=pod

---++++ setPassword( $login, $newPassU, $oldPassU ) -> $boolean

If the $oldPassU matches matches the user's password, then it will
replace it with $newPassU.

If $oldPassU is not correct and not 1, will return 0.

If $oldPassU is 1, will force the change irrespective of
the existing password, adding the user if necessary.

Otherwise returns 1 on success, undef on failure.
Site Name: $Foswiki::cfg{SiteName}
=cut

sub setPassword {
	my ($this, $login, $newUserPassword, $oldUserPassword) = @_;
	my $user_handler = Foswiki::Contrib::DBIStoreContrib::UserHandler::->init($this->{site_handler});
	my $this = shift;
	
	# put an eval here
	$user_handler->database_connection()->{AutoCommit} = 0;
	$user_handler->database_connection()->{RaiseError} = 1;
	my $return_value = undef;
	eval{
		$user_handler->set_to_deferred();
		if($this->checkPassword($login,$oldUserPassword)){
			# true, then change password
			$user_handler->changePassword($login,$newUserPassword);
			$return_value = 1;
		}
		elsif( defined($oldUserPassword) && $oldUserPassword eq '1') {
			# this case is for when the user wants to reset his or her password
			$user_handler->changePassword($login,$newUserPassword);
			$return_value = 1;
		}
		else{
			# false, then produce an error
			$this->{error} = 'System does not support changing passwords';
			$return_value = undef;
		}
		$user_handler->database_connection()->commit;
	};
	if ($@) {
		warn "Rollback - failed to save ($login) for reason:\n $@";
		$user_handler->database_connection()->errstr;
		eval{
			$user_handler->database_connection()->rollback;
		};
	}
	return $return_value;
}

=pod

---++++ setEmails($user, @emails)

Set the email address(es) for the given username.
The engine can't set the email stored in LDAP. But may be the secondary
password manager can.

=cut

sub setEmails {
  my $this = shift;

  return $this->{secondaryPasswordManager}->setEmails(@_)
    if $this->{secondaryPasswordManager};
  
  $this->{error} = 'System does not support setting the email adress';
  return '';
}

=pod

---++++ findUserByEmail( $email ) -> \@users
   * =$email= - email address to look up
Return a list of user objects for the users that have this email registered
with the password manager. This will concatenate the result list of the
LDAP manager with the secondary password manager

=cut

sub findUserByEmail {
  my ($this, $email) = @_;

  $this->{error} = 'System does not support searching for email adresses';
  return '';
}

=pod 

---++++ canFetchUsers() -> boolean

returns true, as we can fetch users

=cut

sub canFetchUsers {
  return 0;
}

=pod 

---++++ fetchUsers() -> new Foswiki::ListIterator(\@users)

returns a FoswikiIterator of loginnames 

=cut

sub fetchUsers {
	my $this = shift;

	#return new Foswiki::ListIterator($users);
	return undef;
}


1;
