# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::Cache::MemoryHash

Implementation of a Foswiki::Cache using an in-memory perl hash.
See Foswiki::Cache for details of the methods implemented by this class.

=cut

package Foswiki::Cache::MemoryHash;

use strict;
use warnings;
use Foswiki::Cache;
use vars qw($sharedCache);

@Foswiki::Cache::MemoryHash::ISA = ('Foswiki::Cache');

sub new {
    my ( $class, $session ) = @_;

    unless ($sharedCache) {
        $sharedCache = bless( $class->SUPER::new($session), $class );
    }

    $sharedCache->init($session);

    return $sharedCache;
}

sub set {
    my ( $this, $key, $obj ) = @_;

    $this->{cache}{ $this->genKey($key) } = $obj;
    return $obj;
}

sub get {
    my ( $this, $key ) = @_;

    return $this->{cache}{ $this->genKey($key) };
}

sub delete {
    my ( $this, $key ) = @_;

    undef $this->{cache}{ $this->genKey($key) };
    return 1;
}

sub clear {
    my $this = shift;

    $this->{cache} = ();
}

sub finish { }

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:
Copyright (C) 2008 Michael Daum http://michaeldaumconsulting.com

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
