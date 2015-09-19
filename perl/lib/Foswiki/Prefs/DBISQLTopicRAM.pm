# See bottom of file for license and copyright information

=pod TML

---+ package Foswiki::Prefs::TopicRAM

This is a preference backend used to get preferences defined in a topic.

=cut

# See documentation on Foswiki::Prefs::BaseBackend to get details about the
# methods.

package Foswiki::Prefs::DBISQLTopicRAM;

use strict;
use warnings;
use Foswiki::Contrib::DBIStoreContrib::Handler ();
use Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler ();

use base ("Foswiki::Prefs::BaseBackend");

# See bottom of file for license and copyright information


sub new {
    my ( $proto, $topicObject ) = @_;

    my $this = $proto->SUPER::new();
    $this->{values} = {};
    $this->{local}  = {};
    # setup the handler
    $this->{site_handler} = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
    my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($this->{site_handler});
    # get the topic row
    my ($web_name,$topic_name) = ($topicObject->web,$topicObject->topic); 
    my $topic_row = $topic_handler->LoadTHRow($web_name,$topic_name);
    $this->{site_handler} = bless $topic_handler, *Foswiki::Contrib::DBIStoreContrib::Handler;
    # Get the information from the backend
    # run the Meta Listener 
    Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler::listener($this->{site_handler},$topicObject,$topic_row);
	$this->parse( $topicObject);
    $this->{topicObject} = $topicObject;

    return $this;
}

sub finish {
    my $this = shift;
    undef $this->{values};
    undef $this->{local};
    undef $this->{topicObject};
}

=pod TML

---++ ObjectMethod topicObject() -> $topicObject

Accessor to the topicObject used to create this object.

=cut

sub topicObject {
    my $this = shift;
    return $this->{topicObject};
}

sub prefs {
    my $this = shift;
    return keys %{ $this->{values} };
}

sub localPrefs {
    my $this = shift;
    return keys %{ $this->{local} };
}

sub get {
    my ( $this, $key ) = @_;
    return $this->{values}{$key} if $this->{values}{$key};
	my $locallevel = $this->{values}{$key}; 
	my ($web,$topic) = ($this->{topicObject}->web,$this->{topicObject}->topic);
    my $mphandler = Foswiki::Contrib::DBIStoreContrib::MetaPreferenceHandler::->init($this->{site_handler});
	my $mpreturn = $mphandler->LoadCascadeACLs($web,$topic,$key);
	my $sitelevel = $mpreturn->{SiteLevel}->{$key};
	my $weblevel = $mpreturn->{WebLevel}->{$key};
	my $topiclevel = $mpreturn->{TopicLevel}->{$key};
	
	return $locallevel unless $locallevel;
	return $topiclevel unless $topiclevel;
	return $weblevel unless $weblevel;
	return $sitelevel unless $topiclevel;
	return undef;
}

sub getLocal {
    my ( $this, $key ) = @_;
    return $this->{local}{$key};
}

sub insert {
    my ( $this, $type, $key, $value ) = @_;

    $this->cleanupInsertValue( \$value );

    my $index = $type eq 'Set' ? 'values' : 'local';
    $this->{$index}{$key} = $value;
    return 1;
}


# parse the prefs after the MetaPreferences Listeners has already loaded this
sub parse {
    my ( $prefs, $topicObject ) = @_;

    # Process text first
    my $key   = '';
    my $value = '';
    my $type;

    # Now process PREFERENCEs
    my @fields = $topicObject->find('PREFERENCE');
    foreach my $field (@fields) {
        my $type  = $field->{type} || 'Set';
        my $value = $field->{value};
        my $name  = $field->{name};
        $prefs->insert( $type, $name, $value );
    }
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
