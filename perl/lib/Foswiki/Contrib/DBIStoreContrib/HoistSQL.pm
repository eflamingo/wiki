# See bottom of file for copyright and license details

=pod TML

---+ package Foswiki::Contrib::DBIStoreContrib::HoistSQL

Static functions to extract SQL expressions from queries. The SQL can
be used to pre-filter topics cached in an SQL DB for more efficient
query matching.

=cut

package Foswiki::Contrib::DBIStoreContrib::HoistSQL;

use strict;

use Foswiki::Infix::Node ();
use Foswiki::Query::Node ();
use Foswiki::Store::DBISQLQuery ();

use constant MONITOR => 0;

# MUST BE KEPT IN LOCKSTEP WITH Foswiki::Infix::Node
# Declared again here because the constants are not defined
# in Foswiki 1.1 and earlier
use constant {
    NAME   => 1,
    NUMBER => 2,
    STRING => 3,
};

BEGIN {
    # Foswiki 1.1 doesn't have makeConstant; monkey-patch it
    unless (defined &Foswiki::Infix::Node::makeConstant) {
	*Foswiki::Infix::Node::makeConstant = sub {
	    my ($this, $type, $val) = @_;
	    $this->{op} = $type;
	    $this->{params} = [ $val ];
	}
    }
}
my $count;
sub counter {
	$count++;
	$count = 0 if $count > 1000000;
	return $count;
}

=pod TML

---++ ObjectMethod hoist($query) -> $sql_statement

Hoisting consists of assembly of a WHERE clause. There may be a
point where the expression can't be converted to SQL, because some operator
(for example, a date operator) can't be done in SQL. But in most cases
the hoisting allows us to extract a set of criteria that can be AND and
ORed together in an SQL statement sufficient to narrow down and isolate
that subset of topics that might match the query.

The result is a string SQL query, and the $query is modified to replace
the hoisted expressions with constants.

=cut
# Checks for AND
# ($node)-> ($fromClause,$whereClause,\@placeHolders)
sub hoist {
    my ($node, $indent) = @_;
	#require Data::Dumper;
	#die Data::Dumper::Dumper($node);
	unless( ref($node->{op})){
		# trivial searches go here #
		# no tableref b/c no tables, no where clause b/c trivial search
		return _generateHoistReturn($node,undef,undef);
	}
    #return undef unless ref( $node->{op} );
    
    $indent ||= '';

    return _hoistB($node, "${indent}|");
	
	

	#my @merged_table_list = _mergeList($tablesRef);
	
	#return _generateHoistReturn($node,\@merged_table_list,$where);
}


# Checks for OR, AND.  If not either of those, then send it to hoistC
sub _hoistB {
    my ($node, $indent) = @_;
	my @tables;
	my ($whereEnd,$placeHolder);
	my @wheres;
    return unless ref( $node->{op} );
	
	my @new_table_list;
	my ($new_where,$where,$table_ref);
	my @paramList;
    if ( $node->{op}->{name} eq '(' ) {
    	warn "hoistB ( \n";
    	# the whole point here is to just add parenthesis
    	# also, there is only one parameter in a set of parenthesis
    	my ($string,$subPH) = _hoistB($node->{params}[0],$indent);
	return (" ( $string ) ",$subPH);

    }
    elsif ( $node->{op}->{name} eq 'or' ) {
    	warn "hoistB OR \n";
    	@paramList = @{$node->{params}};
    	my @or_wheres;
	my @placeholders;
    	foreach my $spl1 (@paramList){
    		my ($string,$subPH) = _hoistB($spl1,$indent);
    		push( @or_wheres, $string);
		push(@placeholders, @{$subPH});
    	}
    	$new_where = " ( ".join(' ) UNION (', @or_wheres)." ) ";
	return ( " ( ".join(' ) UNION (', @or_wheres)." ) ", \@placeholders);
	
    }
    elsif ( $node->{op}->{name} eq 'and' ) {
    	warn "hoistB AND \n";
    	@paramList = @{$node->{params}};
    	my @or_wheres;
	my @placeholders;
    	foreach my $spl1 (@paramList){
    		my ($string,$subPH) = _hoistB($spl1,$indent);
    		push( @or_wheres, $string);
		push(@placeholders, @{$subPH});
    	}
	return ( " ( ".join(' ) INTERSECT (', @or_wheres)." ) ", \@placeholders);
    }
    else {
    	return _hoistC($node, "${indent}|", 0);
	
    }

    return undef;
}

# Checks Equations Only
# ($node,$negated) -> ($table,$cond)
sub _hoistC {
    my ($node, $indent, $negated) = @_;
	my @tables;
    return undef unless ref( $node->{op} );

	
    my $op = $node->{op}->{name}; 
    if ( $op eq '(' ) {
    	warn "hoistC ( \n";
        return _hoistB( $node->{params}[0], "${indent}(", $negated );
    }

    my ($lhs, $rhs, $table, $test);
    my ($ValueTable,$cond,$where,$table_number);
	##### Operation For '!=' #####

    if($op eq '['){
	return _hoistABracket($node);

    }
    else{
	# test the next level for Dot or Slash
	($lhs,$rhs) = ($node->{params}[0],$node->{params}[1]);

	return _hoistADot($node) if $lhs->{op}->{name} eq '.';
	return _hoistASlash($node) if $lhs->{op}->{name} eq '/';

	die "No valid operation.";
    }

	
	return undef;
}

=pod
---++ _hoistABracket
This deals with the equations: table[columnA = valueA and columnB = valueB]
=cut
sub _hoistABracket {
	my $node = shift;
	# get the table name:
	my ($lhs,$rhs) = ($node->{params}[0],$node->{params}[1]);
	my $tablename = $lhs->{params}[0];

	# convert this to a table name
	if ( $Foswiki::Query::Node::aliases{$tablename} ) {
		$tablename = $Foswiki::Query::Node::aliases{$tablename};
	}
	if ( $tablename =~ /^META:(\w+)/ ) {
		# this corresponds to META:rootfields...
		$tablename = $1;
	}
	else{
		# die because there is no matching table
		die "There is no matching table.";
	}

	# special situation here.  Need to call special hoist name
	my ($wherestring,$subPH) = _hoistBBracket($rhs,$tablename);
	my @pp = @{$subPH};
	

	my $alias = Foswiki::Store::DBISQLQuery::getAlias();
	# grab the sql string
	my $string = $alias->{$tablename}->{'bracketsql'};
	
	if($alias->{$tablename}->{'bracketfree'}){
		# make sure the bracket is not empty
		if(scalar(@pp) == 0){
			# this is just a dumby condition that is always true
			$wherestring = ' 1 = 1 ';
		}
		# search and replace FREEDOM (assuming bracket has 'brackfree' => 1
		$string =~ s/FREEDOM/$wherestring/g;
	}
	else{
		die "haven't finished restricted bracket searches yet.";
	}
	return ($string,\@pp)
	#die "Bracket:($string)\n(@pp)";
}	

=pod
---++ _hoistADot
This deals with the equations: table.column = value, results
=cut
sub _hoistADot {
	my $node = shift;
	# lhs: corresponds to table.column, rhs: corresponds to the value
	my ($lhs,$rhs) = ($node->{params}[0],$node->{params}[1]);

	# operator should be =,!=, etc
	my $op = $node->{op}->{name};

	my $table_number = '';



	# let's define the table and column
	my ($tablename,$column) = ($lhs->{params}[0],$lhs->{params}[1]);
	($tablename,$column) = ($tablename->{params}[0],$column->{params}[0]);




	# This changes the in-wiki table name to a META syntax name
	# ie link_to -> LINKTO
	if ( $Foswiki::Query::Node::aliases{$tablename} ) {
		$tablename = $Foswiki::Query::Node::aliases{$tablename};
	}
	if ( $tablename =~ /^META:(\w+)/ ) {
		# this corresponds to META:rootfields...
		$tablename = $1;

		my $cond;

		my $alias = Foswiki::Store::DBISQLQuery::getAlias();
		# convert rhsvalue
		my $site_handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
		my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($site_handler);
		my $rhsvalue = $topic_handler->convert_Var($alias->{$tablename}->{'dotcolumns'}->{$column}->{'from'},
							$alias->{$tablename}->{'dotcolumns'}->{$column}->{'to'},  $node->{params}[1]->{params}[0], 'in');



		#die "RHS:($rhsvalue)(".$alias->{$tablename}->{'dotcolumns'}->{$column}->{'from'}.")(".$alias->{$tablename}->{'dotcolumns'}->{$column}->{'to'}.")";
		my $string = $alias->{$tablename}->{'dotsql'};

	
		# check $op operator safety
		my $safeop = $alias->{$tablename}->{'dotcolumns'}->{$column}->{'safe'};
	
		unless($safeop =~ m/$op/){
			die "Equality operator is not safe($op).\n";
		}
		my @placeholders;
		my ($operator,$operator,$value);

		# check if there is a value function (ie foswiki.sha1bytea('some text')
		$value = $alias->{$tablename}->{'dotcolumns'}->{$column}->{'valuefunction'};

		if( $op eq '=' || $op eq '!=' ){
			$column = $alias->{$tablename}->{'dotcolumns'}->{$column}->{'name'};
			$operator = $op;
			$value = '?' unless defined $value;
			push(@placeholders,$rhsvalue);

		}
		elsif (  $op eq '<' || $op eq '>' || $op eq '<=' || $op eq '>='  ) {
			# this better be a number, or else this operator will fail
			# ...number_name may not exist, however since the operation is safe, just get the 'name'
			my $x001 = $column;
			$column = $alias->{$tablename}->{'dotcolumns'}->{$x001}->{'number_name'};
			$column = $alias->{$tablename}->{'dotcolumns'}->{$x001}->{'name'} unless defined $column;
			
			$operator = $op;
			$value = '?'  unless defined $value;
			push(@placeholders, $rhsvalue);
		}
		elsif( $op eq '~' ){
			# only works on blob values
			# column @@ plainto_tsquery('foswiki.all_languages', value ) 
			$column = $alias->{$tablename}->{'dotcolumns'}->{$column}->{'word_name'};
			$operator = ' @@ ';
			$value = qq{plainto_tsquery('foswiki.all_languages', ? )}; 
			push(@placeholders, $rhsvalue);
		}
		else{
			# die here
			die "operation does not work";
		}
		# this string has HOISTNAME OPERATOR HOISTVALUE, search and replace
		$string =~ s/HOISTNAME/$column/g;

		$string =~ s/OPERATOR/$operator/g;

		$string =~ s/HOISTVALUE/$value/g;

		return ($string,\@placeholders);
	}
	else{
		die "there is no valid table here ($lhs).\n";
	}
}
=pod
---++ _hoistASlash
This deals with the equations: Form/Field = value
=cut
sub _hoistASlash {
	my $node = shift;
	# lhs: corresponds to table.column, rhs: corresponds to the value
	my ($lhs,$rhs) = ($node->{params}[0],$node->{params}[1]);

	# operator should be =,!=, etc
	my $op = $node->{op}->{name};

	my $table_number = '';
	my $site_handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($site_handler);
	

	# let's define the table and column
	my ($form,$field) = ($lhs->{params}[0],$lhs->{params}[1]);
	($form,$field) = ($form->{params}[0],$field->{params}[0]);
	# convert form to topic_key
	$form = $topic_handler->convert_Var('WT','Topics',  $form, 'in');

	my $column = 'value';
	my $tablename = 'META:FORM';
	my $rhsvalue = $node->{params}[1]->{params}[0];
	if ( $tablename =~ /^META:(\w+)/ ) {
		# this corresponds to META:rootfields...
		$tablename = $1;

		my $cond;

		my $alias = Foswiki::Store::DBISQLQuery::getAlias();

		my $string = $alias->{$tablename}->{'slashsql'};

	
		# check $op operator safety
		my $safeop = $alias->{$tablename}->{'slashcolumns'}->{$column}->{'safe'};
	
		unless($safeop =~ m/$op/){
			die "Equality operator is not safe($op).\n";
		}
		my @placeholders;
		my ($operator,$operator,$value);
		if( $op eq '=' || $op eq '!=' ){
			$column = $alias->{$tablename}->{'slashcolumns'}->{$column}->{'name'};
			$operator = $op;
			$value = '?';
			#push(@placeholders,$node->{params}[1]->{params}[0]);

		}
		elsif (  $op eq '<' || $op eq '>' || $op eq '<=' || $op eq '>='  ) {
			# this better be a number, or else this operator will fail
			# ...number_name may not exist, however since the operation is safe, just get the 'name'
			my $x001 = $column;
			$column = $alias->{$tablename}->{'slashcolumns'}->{$x001}->{'number_name'};
			$column = $alias->{$tablename}->{'slashcolumns'}->{$x001}->{'name'} unless defined $column;
			
			$operator = $op;
			$value = '?';
			
			# need to convert the right hand side into a number

			$rhsvalue = $topic_handler->convert_Var('local','epoch',  $rhsvalue, 'in');
			#die "RHS:($rhsvalue)";
			# check if the Value is a number
			# TODO: get a better regex for numbers
			if( $rhsvalue =~ m/\s*([\d,\.]+)\s*/){
				# leave it as is
				
			}
			else{
				# die, because this is not a number
				
			}



			#push(@placeholders, $node->{params}[1]->{params}[0]);
			# 'local',to =>'epoch' 
		}
		elsif( $op eq '~' ){
			# only works on blob values
			# column @@ plainto_tsquery('foswiki.all_languages', value ) 
			$column = $alias->{$tablename}->{'slashcolumns'}->{$column}->{'word_name'};
			$operator = ' @@ ';
			$value = qq{plainto_tsquery('foswiki.all_languages', ? )}; 
			#push(@placeholders, $node->{params}[1]->{params}[0]);
		}
		else{
			# die here
			die "operation does not work";
		}
		
		

		# this string has HOISTNAME OPERATOR HOISTVALUE, search and replace
		# ...get the form and field info
		my $formcol = $alias->{$tablename}->{'slashcolumns'}->{'form'}->{'name'};
		my $fieldcol = $alias->{$tablename}->{'slashcolumns'}->{'field'}->{'name'};
		my @posFORM = _match_positions('SLASHFORM',$string);
		my @posFIELD = _match_positions('SLASHFIELD',$string);
		my @posVALUE = _match_positions('SLASHVALUE',$string);
		my %sorter;
		$sorter{$posFORM[0]} = 'SLASHFORM';
		$sorter{$posFIELD[0]} = 'SLASHFIELD';
		$sorter{$posVALUE[0]} = 'SLASHVALUE';
		foreach my $key (sort keys %sorter) {
			if($sorter{$key} eq 'SLASHFORM'){
				push(@placeholders,$form);
				$string =~ s/SLASHFORM/ $formcol = ? /g;
			}
			elsif($sorter{$key} eq 'SLASHFIELD'){
				push(@placeholders,$field);
				$string =~ s/SLASHFIELD/ $fieldcol = ? /g;
			}
			elsif($sorter{$key} eq 'SLASHVALUE'){
				push(@placeholders,$rhsvalue);
				$string =~ s/SLASHVALUE/$column $operator $value/g;
			}	
		}
		return ($string,\@placeholders);
	}
	else{
		die "there is no valid table here ($lhs).\n";
	}
}


# Expecting a (root level) field access expression. This must be of the form
# <name>
# or
# <rootfield>.<name>
# <rootfield> may be aliased
# Returns a partial SQL statement that can be followed by a condition for
# testing the value.
# A limited set of functions - UPPER, LOWER, 

# ($node)->($table,$column)
sub _hoistValue {
    my ($node, $input_op) = @_;
    my $indent = "";

    my $op = ref( $node->{op}) ? $node->{op}->{name} : '';


    if ( $op eq '(' ) {
        return _hoistValue( $node->{params}[0] );
    }
 
    if ( $op eq '.' ) {
        my $lhs = $node->{params}[0];
        my $rhs = $node->{params}[1];
        if (   !ref( $lhs->{op} ) && !ref( $rhs->{op} )
            && $lhs->{op} == NAME && $rhs->{op} == NAME )
        {
        	# the table name, such as transaction, might have a number attached
        	# like this: transaction_1
        	# make sure to strip off the last number, as well as the underscore #
        	my $table_number = '';
            $lhs = $lhs->{params}[0];
            if( $lhs =~ /^([^_]+)_([0-9]+)$/){
            	$lhs = $1;
            	$table_number = $2;
            }

            $rhs = $rhs->{params}[0];

			# This changes the in-wiki table name to a META syntax name
			# ie link_to -> LINKTO
            if ( $Foswiki::Query::Node::aliases{$lhs} ) {
                $lhs = $Foswiki::Query::Node::aliases{$lhs};
            }
            if ( $lhs =~ /^META:(\w+)/ ) {
		# this corresponds to META:rootfields...
		my $metaTable = $1;

		my $cond;
=pod		
		# we need to check TOPICINFO.isA = user/group/...
		if($metaTable eq 'TOPICINFO' && $rhs eq 'isA'){
			$cond = {op => undef, value => undef, column => $rhs, column_old => $rhs};
			
			# since we are only adding a join, we can return now
			# no need to return a table number
			return ($metaTable,$cond);
		}
		# for other standard queries, get the sql column name to be used in the where clause
		my $newrhs = Foswiki::Store::DBISQLQuery::getHoistAliasColumns($metaTable,$rhs,$input_op,$table_number);
		$cond = {op => undef, value => undef, column => $newrhs, column_old => $rhs};				
		 
		# make sure metaTable also includes _NUMBER in case there are multiple rows to deal with
		$metaTable = $metaTable.'_'.$table_number if $table_number;
=cut
		my $alias = Foswiki::Store::DBISQLQuery::getAlias();

		my $string = $alias->{$metaTable}->{'nested'};



		my @placeholders;
		
		$placeholders[$alias->{$metaTable}->{'nestedcolumns'}->{$rhs}->{'place'}-1] = ''; #form.name
		
		return ($string,{table => $metaTable, placeholders => \@placeholders, column => $rhs});
                #return ($metaTable, $cond);
            }

            if ( $rhs eq 'text' ) {
                # Special case for the text body
                return ('topic.text', 'topic');
            }

            if ( $rhs eq 'raw' ) {
                # Special case for the text body
                return ('topic.raw', 'topic');
            }

            # Otherwise assume the term before the dot is the form name
            return ("EXISTS(SELECT * FROM FORM WHERE FORM.tid=topic.tid AND FORM.name='$lhs') AND FIELD.name='$rhs' AND FIELD.value",
                    "FIELD")
        }
    }
	# this is only for FORM fields
	elsif ( $op eq '/' ) {
		my $lhs = $node->{params}[0];
		my $rhs = $node->{params}[1];
		
		($lhs,$rhs) = ($lhs->{params}[0],$rhs->{params}[0]);
		# HowToForm/Software = 'Ubuntu'
		#die "Bothsides($lhs,$rhs)";
		my $alias = Foswiki::Store::DBISQLQuery::getAlias();

		my $string = $alias->{'FIELD'}->{'nested'};

        	my $site_handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
        	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($site_handler);
        	$lhs = $topic_handler->convert_Var($alias->{'FIELD'}->{'nestedcolumns'}->{'form'}->{'from'}, 
							$alias->{'FIELD'}->{'nestedcolumns'}->{'form'}->{'to'}, $lhs, 'in');



		my @placeholders;
		$placeholders[$alias->{'FIELD'}->{'nestedcolumns'}->{'field'}->{'place'}-1] = $rhs; #field;
		$placeholders[$alias->{'FIELD'}->{'nestedcolumns'}->{'form'}->{'place'}-1] = $lhs; #form;
		$placeholders[$alias->{'FIELD'}->{'nestedcolumns'}->{'value'}->{'place'}-1] = ''; #value; we won't know this value until hoistC
		return ($string,{table => 'FIELD', placeholders => \@placeholders, column => 'value'});
	}

    elsif ( !ref( $node->{op} ) && $node->{op} == NAME ) {
        # A simple name
        if ( $node->{params}[0] =~ /^(name|web|text|raw)$/ ) {

            # Special case for the topic name, web or text body
            return ("topic.$1", 'topic');
        }
        else {
            return ("FIELD.name='$node->{params}[0]' AND FIELD.value",
                    'FIELD');
        }
    }

    print STDERR "\tFAILED\n" if MONITOR;
    return (undef, undef);
}

# Expecting a constant
# ($node)->STRING or number
sub _hoistConstant {
    my $node = shift;
    warn "hoistConstant ( \n";
    if (
        !ref( $node->{op} )
        && (   $node->{op} == STRING
            || $node->{op} == NUMBER )
      )
    {
    	
        return $node->{params}[0];
    }
    return undef;
}

# for dealing with AND's and OR's in Tx[account = 'Cash' OR account = 'Paypal']
sub _hoistBBracket {
	my ($node, $tablename ) = (shift,shift);

	#require Data::Dumper;
	#die "LHS:".Data::Dumper::Dumper($node)."\n\nRHS:$tablename\n\n";

	return unless ref( $node->{op} );
	
	if ( $node->{op}->{name} eq '(' ) {
		# the whole point here is to just add parenthesis
    		# also, there is only one parameter in a set of parenthesis
		my ($string,$subPH) = _hoistBBracket($node->{params}[0],$tablename);
		return (" ( $string ) ",$subPH);
	}
	elsif ( $node->{op}->{name} eq 'or' ) {

		my @paramList = @{$node->{params}};
		my @or_wheres;
		my @placeholders;
		foreach my $spl1 (@paramList){
			my ($string,$subPH) = _hoistBBracket($spl1,$tablename);
			push( @or_wheres, $string);
			push(@placeholders, @{$subPH});
		}
		return ( " ( ".join(' ) OR (', @or_wheres)." ) ", \@placeholders);
		
	}
	elsif ( $node->{op}->{name} eq 'and' ) {

		my @paramList = @{$node->{params}};
		my @or_wheres;
		my @placeholders;
		foreach my $spl1 (@paramList){
    			my ($string,$subPH) = _hoistBBracket($spl1,$tablename);
    			push( @or_wheres, $string);
			push(@placeholders, @{$subPH});
		}
		return ( " ( ".join(' ) AND (', @or_wheres)." ) ", \@placeholders);
	}
	else {
		return _hoistCBracket($node, $tablename);
	}

	return undef;
}
# for dealing with equations names in Tx[account = 'Cash' OR account = 'Paypal']
sub _hoistCBracket {
	my ($node, $tablename ) = (shift,shift);

	my $op = $node->{op}->{name};
	my ($lhs,$rhs) = ($node->{params}[0],$node->{params}[1]);

	# rhs is the value, feed it into the constant
	$rhs = _hoistConstant($rhs);


	# lhs is the column name
	# fetch the SQL column name via Tablename.Columnname
	$lhs = $lhs->{params}[0];
        my $site_handler = Foswiki::Contrib::DBIStoreContrib::Handler::->new();
        my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->init($site_handler);
	my $alias = Foswiki::Store::DBISQLQuery::getAlias();
        $rhs = $topic_handler->convert_Var($alias->{$tablename}->{'bracketcolumns'}->{$lhs}->{'from'}, 
							$alias->{$tablename}->{'bracketcolumns'}->{$lhs}->{'to'}, $rhs, 'in');


	

	# TODO: check $op safety via $alias
	my $safeop = $alias->{$tablename}->{'bracketcolumns'}->{$lhs}->{'safe'};

	unless($safeop =~ m/$op/){
		die "Equality operator is not safe.\n";
	}
	my @placeholders;
	my ($column,$operator,$value);
	# check if there is a value function
	$value = $alias->{$tablename}->{'bracketcolumns'}->{$lhs}->{'valuefunction'};

	if( $op eq '=' || $op eq '!=' ){
		$column = $alias->{$tablename}->{'bracketcolumns'}->{$lhs}->{'name'};
		$operator = $op;
		$value = '?' unless defined $value;
		push(@placeholders, $rhs);

	}
	elsif (  $op eq '<' || $op eq '>' || $op eq '<=' || $op eq '>='  ) {
		# this better be a number, or else this operator will fail
		# ...number_name may not exist, however since the operation is safe, just get the 'name'
		$column = $alias->{$tablename}->{'bracketcolumns'}->{$lhs}->{'number_name'};
		$column = $alias->{$tablename}->{'bracketcolumns'}->{$lhs}->{'name'} unless defined $column;
		$operator = $op;
		$value = '?' unless defined $value;
		push(@placeholders, $rhs);

	}
	elsif( $op eq '~' ){
		# only works on blob values
		# column @@ plainto_tsquery('foswiki.all_languages', value ) 
		$column = $alias->{$tablename}->{'bracketcolumns'}->{$lhs}->{'word_name'};
		$operator = ' @@ ';
		$value = qq{plainto_tsquery('foswiki.all_languages', ? )}; 
		push(@placeholders, $rhs);

	}
	else{
		# die here
	}
	die "Column does not exist." unless defined $column ;
	die "Operator does not exist." unless defined $operator ;
	die "Value does not exist." unless scalar(@placeholders) > 0 ;
	return (" $column $operator $value ",\@placeholders);
}

# this is the return from the Hoist Function
sub _generateHoistReturn {
	my $node = shift;
	my $tablesRef = shift;
	my $where = shift;

	#### make the web picker ####
	# kind of messy, but only way to get the web_key into the where clause
	my $webPickerFull = "";
	if($node->{web_key}){
		my @web_keys = @{$node->{web_key}};
		my $webPicker;
		my @WebClauses;
		foreach my $wkey (@web_keys){
			$webPicker = 'webs."key" = $#S#$ReplacedWithWebKeyLaterButHopeFullyNoOneEverSearchesForThis$#F#$';
			push(@WebClauses,$webPicker);
		}
		$webPickerFull = ' AND ('.join(' OR ',@WebClauses).') ' if $webPicker;
	}
	#### Get the SQL statement (minus the Select part )####
	my ($fromClause,$whereClause) = getSQLFromWhere($tablesRef,$where);
	
	
	my $sitePicker = ' webs.site_key = $#S#$ReplacedWithSiteKeyLaterButHopeFullyNoOneEverSearchesForThis$#F#$ ';
	my $current_revision_only_picker = ' AND thn."key" = t1n.link_to_latest ' unless $node->{history} && $node->{history} ne 'now';
	my ($PClause,$placeholder) = placeHolderize(" FROM $fromClause WHERE $sitePicker $current_revision_only_picker $webPickerFull ", $whereClause);

	return ($PClause,$placeholder);
}

sub uniq {
    return keys %{{ map { $_ => 1 } @_ }};
}
# ($tables,$where)->($tables,$where)
sub getSQLFromWhere{
	my ($tablesRef,$where) = @_;
	my $TH = Foswiki::Store::DBISQLQuery::getTableName('Topic_History');
	my $BS = Foswiki::Store::DBISQLQuery::getTableName('Blob_Store');
	my $Topics = Foswiki::Store::DBISQLQuery::getTableName('Topics');
	my $MPH = Foswiki::Store::DBISQLQuery::getTableName('Meta_Preferences');
	my $Webs = Foswiki::Store::DBISQLQuery::getTableName('Webs');
	my $thfrom = qq/ $TH thn \n/;
	# this join is to get the current topic information (current web name and topic name if thn is a past version, not the current version of a topic
	$thfrom .= qq/ INNER JOIN ($Topics t1n
			INNER JOIN $Webs webs ON t1n.current_web_key = webs."key"
			LEFT JOIN $MPH mph_deny ON t1n.link_to_latest = mph_deny.topic_history_key AND mph_deny."name" = 'DENYTOPICVIEW'
			LEFT JOIN $MPH mph_allow ON t1n.link_to_latest = mph_allow.topic_history_key AND mph_allow."name" = 'ALLOWTOPICVIEW'  
			INNER JOIN $BS tname ON t1n.current_topic_name = tname."key"
	  ) ON thn.topic_key = t1n."key" \n/;
	
	my @listOfJoins;
	my %alreadydoneHash;
	# create the FROM clause
	foreach my $utable (@$tablesRef) {
		next if $alreadydoneHash{$utable};
		# need to check for _NUMBER in the table name
		# first, strip _NUMBER
		my $tnum = '';
		if( $utable =~ /^([^_]+)_([0-9]+)$/){
			$utable = $1;
			$tnum = $2;
		}
		$thfrom .= Foswiki::Store::DBISQLQuery::getHoistAliasJoins($utable,$tnum)."\n";
		$alreadydoneHash{$utable} = 1;
	}
	
	return ($thfrom,$where);
}
# ($SelectStatement)-> ($SelectStatementNaked,@placeholder)
sub placeHolderize
{
	my $orig = shift;
	my $leftoverWhere = shift;
	my $statement = "";
	my $statementWithWhere = $orig." AND $leftoverWhere";
	my $statementNoWhere = $orig;
	
	# check if $leftoverWhere is null (or has only spaces)
	if ( $leftoverWhere =~ /^\s+$/ ) {
		# this corresponds to META:rootfields...
		$leftoverWhere = undef;
	}
	
	# pulls values out of where statement
	# the quote is $#S#$ blah $#F#$
	my @placeHolderWithWhere = ($statementWithWhere =~ m/\$#S#\$(.*?)\$#F#\$/g);
	my @placeHolderNoWhere = ($statementNoWhere =~ m/\$#S#\$(.*?)\$#F#\$/g);
	my ($numHolderWithWhere,$numHolderNoWhere) = (scalar(@placeHolderWithWhere),scalar(@placeHolderNoWhere));
	my $placeHolderRef;
	# changed this cond from $numHolderWithWhere > $numHolderNoWhere to $leftoverWhere
	if($leftoverWhere){
		# means there was a search term put in	
		# %SEARCH{"preferences.name = 'WEBFORMS'" web="Main" type="query" nonoise="on" format="   * [[$web.$topic][$web $topic]]" }% 
		$statement = $statementWithWhere;
		$placeHolderRef = \@placeHolderWithWhere;
	}
	else{
		# we are banning this trivial search as of 2011-12-08
		# trivial search 
		# %SEARCH{"1" web="Main" type="query" nonoise="on" format="   * [[$web.$topic][$web $topic]]" }%
		$statement = $statementNoWhere;
		$placeHolderRef = \@placeHolderNoWhere;
	}
	
	$statement =~ s/(\$#S#\$.*?\$#F#\$)/\?/g; # replaces the quotes and values with '?' placeholders for use in the DBI prepare statement
	
	#$statement = $orig unless scalar(@placeHolder)>0;

	return ($statement,$placeHolderRef);
}
# used for merging lists of tables
sub _mergeList {
	my $old_table = shift;
	my %checker;
	foreach my $x (@$old_table){
		next if $checker{$x}; 
		$checker{$x} = 1;
	}
	return (keys %checker);
}


sub _match_positions {
    my ($regex, $string) = @_;
    return if not $string =~ /$regex/;
    return ($-[0], $+[0]);
}


1;
__DATA__

Module of Foswiki - The Free and Open Source Wiki, http://foswiki.org/, http://Foswiki.org/

Copyright (C) 2010 Foswiki Contributors. All Rights Reserved.
Foswiki Contributors are listed in the AUTHORS file in the root
of this distribution. NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.

Author: Crawford Currie http://c-dot.co.uk
