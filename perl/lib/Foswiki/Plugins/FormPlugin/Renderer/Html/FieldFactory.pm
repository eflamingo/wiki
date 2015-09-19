# See bottom of file for license and copyright information

package Foswiki::Plugins::FormPlugin::Renderer::Html::FieldFactory;

use strict;
use warnings;
=pod
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::BaseMulti();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Button();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Checkbox();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Date();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Dropdown();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Field();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Hidden();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Password();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Radio();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Select();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Submit();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Text();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Textarea();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Textonly();
use Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Upload();
=cut
=pod

=cut

sub getField {
    my ($type) = @_;

    return if !$type;
    $type = 'Checkbox' if $type eq 'checkbox+buttons';    

    my $field;
=pod
    my $class = 'Foswiki::Plugins::FormPlugin::Renderer::Html::Field::' . ucfirst($type);

    $type = ucfirst($type);
    #eval 'require '.$class.'; $field = '.$class.'::new->();';
    my %funcmapper = (
'BaseMulti' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::BaseMulti::new,
'Button' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Button::new,
'Checkbox' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Checkbox::new,
'Date' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Date::new,
'Dropdown' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Dropdown::new,
'Field' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Field::new,
'Hidden' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Hidden::new,
'Password' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Password::new,
'Radio' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Radio::new,
'Select' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Select::new,
'Submit' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Submit::new,
'Text' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Text::new,
'Textarea' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Textarea::new,
'Textonly' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Textonly::new,
'Upload' => \&Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Upload::new 
    );
    
    $field = $funcmapper{$type}();
#    require Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Text;
#    $field = Foswiki::Plugins::FormPlugin::Renderer::Html::Field::Text->new();
=cut
    my $class =
      'Foswiki::Plugins::FormPlugin::Renderer::Html::Field::' . ucfirst($type);

    eval "use $class; \$field = $class->new();";

    if ( !$field && $@ ) {
        die
"Foswiki::Plugins::FormPlugin::Renderer::Html::FieldFactory : Could not create field of type $type.\n";
    }

    return $field;
}

1;

# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (c) 2007-2011 Arthur Clemens, Sven Dowideit, Eugen Mayer
# All Rights Reserved. Foswiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the installation root.
