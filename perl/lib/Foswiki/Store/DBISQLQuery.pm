# nothing here
package Foswiki::Store::DBISQLQuery;


use strict;
use warnings;

use Foswiki::Store::Interfaces::QueryAlgorithm ();
our @ISA = ( 'Foswiki::Store::Interfaces::QueryAlgorithm' );

use Foswiki::Store::Interfaces::SearchAlgorithm ();
use Foswiki::Contrib::DBIStoreContrib::HoistSQL ();
use Foswiki::Contrib::DBIStoreContrib::HoistREs ();
use Foswiki::Search::Node      ();
use Foswiki::Meta              ();
use Foswiki::Search::InfoCache ();
use Foswiki::Search::ResultSet ();
use Foswiki::MetaCache         ();
use Foswiki::Query::Node       ();
use Foswiki::Query::HoistREs   ();
use Foswiki::Contrib::DBIStoreContrib::TopicHandler ();
use Foswiki::Contrib::DBIStoreContrib::ResultSet ();


sub getTableName {
	my $tablename = shift;
	return Foswiki::Contrib::DBIStoreContrib::Handler::returnHandlerTables($tablename); 
} 
my $HoistAlias = {
	'PREFERENCE' => {
		'columns' => { 
			'name' => { from => '',to =>'' ,name => 'mph."name"'}, 
			'value' => { from => '',to =>'' ,name => 'mph."value"'} 
		},
		# there are not always preferences attached, so LEFT JOIN
		'joins'=> ' LEFT JOIN '.getTableName('Meta_Preferences').' mph ON thn."key" = mph.topic_history_key ' 
	},# -------
	'FORM' => {
		'dotsql' => 'SELECT DISTINCT dfdata.topic_history_key as thkey
					FROM
					'.getTableName('Data_Field').' dfdata
					  INNER JOIN ( SELECT dfdef.field_key as field_key
						FROM
							'.getTableName('Definition_Field').' dfdef
								INNER JOIN '.getTableName('Topic_History').' thdef  ON thdef."key" = dfdef.topic_history_key
						WHERE 
							HOISTNAME OPERATOR HOISTVALUE
						) as dfdefinition ON dfdefinition.field_key = dfdata.definition_field_key
	
			',
		'dotcolumns' => {
			'name' => { from => 'WT',to =>'Topics' , name => 'thdef.topic_key', place => 2, safe => '=|!=' }
		},
		'slashsql' => 'SELECT DISTINCT dfdata.topic_history_key as thkey
					FROM
					'.getTableName('Data_Field').' dfdata
					  INNER JOIN '.getTableName('Blob_Store').' dfdatablob ON dfdata.field_value = dfdatablob."key"
					  INNER JOIN ( SELECT dfdef.field_key as field_key
						FROM
							'.getTableName('Definition_Field').' dfdef
								INNER JOIN '.getTableName('Topic_History').' thdef  ON thdef."key" = dfdef.topic_history_key
						WHERE 
							dfdef.field_name = (SELECT dfdefname."key" FROM '.getTableName('Blob_Store').' dfdefname WHERE SLASHFIELD )
							AND
							SLASHFORM
						) as dfdefinition ON dfdefinition.field_key = dfdata.definition_field_key
				WHERE 
					SLASHVALUE
	
			',
		'slashcolumns' => {
			'form' => { from => 'WT',to =>'Topics', name => 'thdef.topic_key' , safe => '=' }, # <-- search and replace with SLASHFORM, operator is always '='
			'field' => { from => '',to =>'', name => 'dfdefname."value"', safe => '=' },# <-- search and replace with SLASHFIELD, operator is always '='
			# BLOBVALUE search and replace
			'value' => { from => '',to =>'' , name => 'dfdatablob."value"', word_name => 'dfdatablob.value_vector', number_name => 'dfdatablob.number_vector'
				, safe => '=|!=|~|>|<|>=|<=' }
		}
	},# -------	
	'FIELD' => {
		'slashsql' => 'SELECT DISTINCT dfdata.topic_history_key as thkey
					FROM
					'.getTableName('Data_Field').' dfdata
					  INNER JOIN '.getTableName('Blob_Store').' dfdatablob ON dfdata.field_value = dfdatablob."key"
					  INNER JOIN ( SELECT dfdef.field_key as field_key
						FROM
							'.getTableName('Definition_Field').' dfdef
								INNER JOIN '.getTableName('Topic_History').' thdef  ON thdef."key" = dfdef.topic_history_key
						WHERE 
							dfdef.field_name = (SELECT dfdefname."key" FROM '.getTableName('Blob_Store').' dfdefname WHERE dfdefname."value" = ? )
							AND
							thdef.topic_key = ? 
						) as dfdefinition ON dfdefinition.field_key = dfdata.definition_field_key
				WHERE 
					HOISTNAME OPERATOR HOISTVALUE
	
			',
		'slashcolumns' => {
			'form' => { from => 'WT',to =>'Topics' ,place => 2 },
			'field' => { from => '',to =>'' ,place => 1 },
			# BLOBVALUE search and replace
			'value' => { from => '',to =>'' ,place => 3, name => 'dfdatablob."value"', word_name => 'dfdatablob.value_vector', number_name => 'dfdatablob.number_vector' }
		}
		
	},# -------
	'FILEATTACHMENT' => {
		'columns' => 0 
	},# -------
	'TOPICINFO' => {
		'dotsql' => 'SELECT DISTINCT tho."key" as thkey
					FROM
					'.getTableName('Topic_History').' tho
					INNER JOIN	'.getTableName('Blob_Store').' tho_tname ON tho.topic_name = tho_tname."key"
					INNER JOIN	'.getTableName('Blob_Store').' tho_tcontent ON tho.topic_content = tho_tcontent."key"
				WHERE HOISTNAME OPERATOR HOISTVALUE
			',
		'dotcolumns' => {
			'author' => { from => 'WT',to =>'Users' ,name => 'tho.user_key',safe => '=|!='}, 
			'date' => { from => 'local',to =>'epoch' ,name => 'tho.timestamp_epoch',safe => '=|!=|>|<|>=|<='}, 
			'version' => { from => '',to =>'' ,name => ' tho.revision ',safe => '=|!=|>|<|>=|<='},# revision and version are the same
			'revision' => { from => '',to =>'' ,name => ' tho.revision ',safe => '=|!=|>|<|>=|<='},
			'web' => { from => 'W',to =>'Webs' ,name => ' tho.web_key ',safe => '=|!='},
			'topic' => { from => '',to =>'' ,name => ' tho_tname."value" ', word_name => ' tho_tname.value_vector ', number_name => ' tho_tname.number_vector '
				, safe => '=|!=|~' },
			'content' => { from => '',to =>'' , word_name => ' tho_tcontent.value_vector '
				, safe => '~' }
		},
		'bracketsql' => 'SELECT DISTINCT tho."key" as thkey
					FROM
					'.getTableName('Topic_History').' tho
					INNER JOIN	'.getTableName('Blob_Store').' tho_tname ON tho.topic_name = tho_tname."key"
					INNER JOIN	'.getTableName('Blob_Store').' tho_tcontent ON tho.topic_content = tho_tcontent."key"
				WHERE FREEDOM
			',
		'bracketfree' => 1,
		'bracketcolumns' => {
			'author' => { from => 'WT',to =>'Users' ,name => 'tho.user_key',safe => '=|!='}, 
			'date' => { from => 'local',to =>'epoch' ,name => 'tho.timestamp_epoch',safe => '=|!=|>|<|>=|<='}, 
			'version' => { from => '',to =>'' ,name => ' tho.revision ',safe => '=|!=|>|<|>=|<='},# revision and version are the same
			'revision' => { from => '',to =>'' ,name => ' tho.revision ',safe => '=|!=|>|<|>=|<='},
			'web' => { from => 'W',to =>'Webs' ,name => ' tho.web_key ',safe => '=|!='},
			'topic' => { from => '',to =>'' ,name => ' tho_tname."value" ', word_name => ' tho_tname.value_vector ', number_name => ' tho_tname.number_vector '
				, safe => '=|!=|~' },
			'content' => { from => '',to =>'' , word_name => ' tho_tcontent.value_vector '
				, safe => '~' }
		},
	},# -------
	'TOPICPARENT' => {
		'dotsql' => 'SELECT DISTINCT l1.topic_history_key as thkey
					FROM
					'.getTableName('Links').' l1
					WHERE
						l1.link_type = \'PARENT\' AND HOISTNAME OPERATOR HOISTVALUE
			',
		'dotcolumns' => {
			'name' => { from => 'WT',to =>'Topics' ,name => 'l1.destination_topic', safe => '=|!='}
		}

	},# -------
	'TOPICMOVED' => {
		'dotsql' => 'SELECT DISTINCT thf."key" as thkey
					FROM
					'.getTableName('Topic_History').' thi 
					INNER JOIN '.getTableName('Topic_History').' thf 
					  ON thi.topic_key = thf.topic_key AND thi.revision + 1 = thf.revision 
					WHERE (thi.web_key != thf.web_key OR thi.topic_name != thf.topic_name) AND (HOISTNAME OPERATOR HOISTVALUE)
			',
		'dotcolumns' => {
			'by' => { from => 'WT',to =>'Users' ,name => 'thf.user_key', safe => '=|!='}, 
			'date' => { from => 'local',to =>'epoch' ,name => 'thf.timestamp_epoch', safe => '=|!=|>|<|>=|<='}, 
			'from_web' => { from => 'W',to =>'Webs' ,name => 'thi.web_key', safe => '=|!='}, 
			'to_web' => { from => 'W',to =>'Webs' ,name => 'thf.web_key', safe => '=|!='},
			# topicmoved does not allow Full Text Searches...
			'from_topic' => { from => '',to =>'' ,name => 'thi.topic_name', valuefunction => ' foswiki.sha1bytea( ? ) ', safe => '=|!='}, 
			'to_topic' => { from => '',to =>'' ,name => 'thf.topic_name', valuefunction => ' foswiki.sha1bytea( ? ) ', safe => '=|!='}
		}, 
		'bracketsql' => 'SELECT DISTINCT thf."key" as thkey
					FROM
					'.getTableName('Topic_History').' thi 
					INNER JOIN '.getTableName('Topic_History').' thf 
					  ON thi.topic_key = thf.topic_key AND thi.revision + 1 = thf.revision AND 
					WHERE (thi.web_key != thf.web_key OR thi.topic_name != thf.topic_name) AND (FREEDOM)
			',
		'bracketfree' => 1,
		'bracketcolumns' => {
			'by' => { from => 'WT',to =>'Users' ,name => 'thf.user_key', safe => '=|!='}, 
			'date' => { from => 'local',to =>'epoch' ,name => 'thf.timestamp_epoch', safe => '=|!=|>|<|>=|<='}, 
			'from_web' => { from => 'W',to =>'Webs' ,name => 'thi.web_key', safe => '=|!='}, 
			'to_web' => { from => 'W',to =>'Webs' ,name => 'thf.web_key', safe => '=|!='},
			# topicmoved does not allow Full Text Searches...
			'from_topic' => { from => 'text',to =>'sha1' ,name => 'thi.topic_name', valuefunction => ' foswiki.sha1bytea( ? ) ', safe => '=|!='}, 
			'to_topic' => { from => 'text',to =>'sha1' ,name => 'thf.topic_name', valuefunction => ' foswiki.sha1bytea( ? ) ', safe => '=|!='}
		}
	},# -------
	'CREATEINFO' => {
		'bracketsql' => 'SELECT DISTINCT tho."key" as thkey
					FROM
					'.getTableName('Topic_History').' tho
					WHERE tho.revision = 1 AND (FREEDOM)
					
			',
		'bracketfree' => 1,
		'bracketcolumns' => {
			'author' => { from => 'WT',to =>'Users' ,name => 'tho.user_key',safe => '=|!='}, 
			'date' => { from => 'local',to =>'epoch' ,name => 'tho.timestamp_epoch',safe => '=|!=|>|<|>=|<='}, 
			'version' => { from => '',to =>'' ,name => ' tho.revision ',safe => '=|!=|>|<|>=|<='},# revision and version are the same
			'revision' => { from => '',to =>'' ,name => ' tho.revision ',safe => '=|!=|>|<|>=|<='},
			'web' => { from => 'W',to =>'Webs' ,name => ' tho.web_key ',safe => '=|!='},
			'topic' => { from => '',to =>'' ,name => ' tho_tname."value" ', word_name => ' tho_tname.value_vector ', number_name => ' tho_tname.number_vector '
				, safe => '=|!=|~' }
		}
	},# -------
	'LINKTO' => { 
		'dotsql' => 'SELECT DISTINCT l1.topic_history_key as thkey
					FROM
					'.getTableName('Links').' l1
					WHERE
						l1.link_type = \'LINK\' AND HOISTNAME OPERATOR HOISTVALUE
			',
		'dotcolumns' => {
			'name' => { from => 'WT',to =>'Topics' ,name => 'l1.destination_topic', safe => '=|!='},
			'revision' => { from => 'WTR',to =>'Topic_History' ,name => 'l1.destination_topic_history', safe => '=|!='}
		}
	},# ------- think of LINKTO as link to this topic from where?
	'LINKFROM' => { 
		'dotsql' => 'SELECT DISTINCT l1.topic_history_key as thkey
					FROM
					'.getTableName('Links').' l1
					WHERE
						l1.link_type = \'LINK\' AND HOISTNAME OPERATOR HOISTVALUE
			',
		'dotcolumns' => {
			'name' => { from => 'WT',to =>'Topics' ,name => 'l1.destination_topic', safe => '=|!='},
			'revision' => { from => 'WTR',to =>'Topic_History' ,name => 'l1.destination_topic_history', safe => '=|!='}
		}
	},  # ------- think of LINKFROM as link from this topic to where?
	'USERS' => { 
		'columns' => {
			'topic' => { from => 'WT',to =>'Topics' ,name => ' u1.user_topic_key '},
			'login' => { from => '',to =>'' ,name => ' u1.current_login_name '},
			'country' => { from => '',to =>'' ,name => ' uh1.country '}
		},
		# the topic may or may not be a User Topic, so LEFT JOIN
		'joins' => ' LEFT JOIN ('.getTableName('Users').' u1 INNER JOIN '.getTableName('User_History').' uh1 ON uh1."key" = u1.link_to_latest )
					 ON thn.topic_key = u1.user_topic_key '
	},  # ------- User info can be gotten from here
	'GROUPS' => { 
		'columns' => {
			'topic' => { from => 'WT',to =>'Topics' ,name => 'g1.group_topic_key'}
		},
		# the topic may or may not be a Group Topic, so LEFT JOIN
		'joins' => ' LEFT JOIN '.getTableName('Groups').' g1 ON thn.topic_key = g1.group_topic_key '
	},  # ------- Group info can be gotten from here
	'ACCOUNT' => { 
		'bracketsql' => 'SELECT 
				  DISTINCT thAccounts."key"  as thkey
				FROM 
				  '.getTableName('Splits').' s1
					INNER JOIN '.getTableName('Topic_History').' thAccounts ON s1.accounts_key = thAccounts.topic_key
				WHERE FREEDOM
			',
		'bracketfree' => 1,
		'bracketcolumns' => {
			'transaction' => { from => 'WT',to =>'Topics', name => 's1.transaction_key', safe => '=|!='  },
			'amount' => { from => '',to =>'', name => 's1.amount', safe => '=|!=|<|>|<=|>='  }
		},
		'dotsql' => 'SELECT 
				  DISTINCT thAccounts."key"  as thkey
				FROM 
				  '.getTableName('Splits').' s1
					INNER JOIN '.getTableName('Topic_History').' thAccounts ON s1.accounts_key = thAccounts.topic_key
				WHERE HOISTNAME OPERATOR HOISTVALUE
			',
		'dotcolumns' => {
			'transaction' => { from => 'WT',to =>'Topics', name => 's1.transaction_key', safe => '=|!='  },
			'amount' => { from => '',to =>'', name => 's1.amount', safe => '=|!=|<|>|<=|>='  }
		}

	},  # ------- Same as Link_To, use this when looking for accounts
	'TRANSACTION' => { 
		'bracketsql' => 'SELECT 
				  DISTINCT thTx."key" as thkey
				FROM 
				  '.getTableName('Splits').' s1
					INNER JOIN '.getTableName('Topic_History').' thTx ON s1.transaction_key = thTx.topic_key
				WHERE FREEDOM
			',
		'bracketfree' => 1,
		'bracketcolumns' => {
			'account' => { from => 'WT',to =>'Topics', name => 's1.accounts_key', safe => '=|!='   },
			'amount' => { from => '',to =>'', name => 's1.amount', safe => '=|!=|<|>|<=|>='   }
		},
		'dotsql' => 'SELECT 
				  DISTINCT thTx."key"  as thkey
				FROM 
				  '.getTableName('Splits').' s1
					INNER JOIN '.getTableName('Topic_History').' thTx ON s1.transaction_key = thTx.topic_key
				WHERE HOISTNAME OPERATOR HOISTVALUE
			',
		'dotcolumns' => {
			'account' => { from => 'WT',to =>'Topics', name => 's1.accounts_key', safe => '=|!='  },
			'amount' => { from => '',to =>'', name => 's1.amount', safe => '=|!=|<|>|<=|>='  }
		}
	},  # ------- same as Link_From, use this when looking for transactions
	'CDR' => { 
		'columns' => {
			'sender' => { from => 'WT',to =>'Users' ,name => 'cdr.caller_key'},
			'receiver' => { from => 'WT',to =>'Users' ,name => 'cdr.callee_key'},
			'callsec' => { from => '',to =>'' ,name => 'cdr.billsec'},
			'answertime' => { from => 'local',to =>'epoch' ,name => 'cdr.answer_epoch'},
			'context' => { from => 'WT',to =>'Topics' ,name => 'cdr.context'},
			'source_number' => { from => '',to =>'' ,name => 'cdr.source_number'},
			'destination_number' => { from => '',to =>'' ,name => 'cdr.destination_number'}
		},
		# the source_number can be a local number or 'Unknown' if the person is calling from skype
		# also, the context maybe 'public' CDR_Topics
		'joins' => ' LEFT JOIN ('.getTableName('CDR').' cdr INNER JOIN '.getTableName('CDR_Topics').' cdrts ON cdr.call_uuid = cdrts.call_history_key ) ON thn.topic_key = cdrts.topic_key '
	},  # ------- same as Link_From, use this when looking for transactions
	'ORDERS' => { 
		'columns' => {
			'owner' => { from => 'WT',to =>'Users' ,name => ' contracts.owner_key '},
			'product' => { from => 'WT',to =>'Topics' ,name => ' pd.topic_key '},
			'product_revision' => { from => '',to =>'' ,name => ' pd.revision '},
			'terms' => { from => 'WT',to =>'Topics' ,name => ' terms.topic_key '},
			'terms_revision' => { from => '',to =>'' ,name => ' terms.revision '},
			'post_date' => { from => 'local',to =>'epoch' ,name => ' ob.post_date '},
			'fill_date' => { from => 'local',to =>'epoch' ,name => ' ob.fill_date '},
			'start' => { from => 'local',to =>'epoch' ,name => ' contracts.start_date '},
			'end' => { from => 'local',to =>'epoch' ,name => ' contracts.end_date '}			
		},
		# this join is really, really nasty
		'joins' => ' LEFT JOIN (
			'.getTableName('Order_Book').' ob 
				INNER JOIN ( '.getTableName('Topic_History').' terms INNER JOIN '.getTableName('Contracts').' contracts ON terms."key" = contracts.type_of_contract) ON ob.contract_id = contracts.contract_id 
				INNER JOIN '.getTableName('Topic_History').' pd ON ob.product_type = pd."key" ) 
		ON thn.topic_key = ob.order_id '
	},  # ------- the above table is for Orders in the Accounts Table 
	'CREDITHISTORY' => { 
		'columns' => {
			'owner' => { from => 'WT',to =>'Users' ,name => 'ch21.user_key'},
			'amount' => { from => '',to =>'' ,name => ' ch21.amount '},
			'currency' => { from => '',to =>'' ,name => ' ch21.currency '}
		}, 
		# the order_id in the join comes from Order_Book, but the order_id in that table has a foreign key contraint on the Topic table
		'joins' => ' LEFT JOIN '.getTableName('Credit_History').' ch21 ON thn."key" = ch21."key" '
	},  # ------- for booking credit payments (credit as in store points that can be spent at e-flamingo.net, not related to accounting splits)
	'CREDITBALANCE' => { 
		'columns' => {
			'balance' => { from => '',to =>'' ,name => ' cb98.balance '},
			'currency' => { from => '',to =>'' ,name => ' cb98.currency '}
		}, 
		# the topic may or may not be a User Topic, so LEFT JOIN
		'joins' => ' LEFT JOIN ('.getTableName('Users').' cbuser INNER JOIN '.getTableName('Credit_Balance').' cb98 ON cbuser."key" = cb98.user_key ) ON thn.topic_key = cbuser.user_topic_key '
	},  # ------- User Credit Balance info can be gotten from here
	'DIDINVENTORY' => { 
		'columns' => {
			'full_number' => { from => '',to =>'' ,name => ' didinv.full_number '},
			'owner' => { from => 'WT',to =>'Users' ,name => ' didinv.owner_key '},
			'forward_site' => { from => 'WT',to =>'Topics' ,name => ' sididinv.topic_key '}
		}, 
		# the topic may or may not be a User Topic, so LEFT JOIN
		'joins' => ' LEFT JOIN ('.getTableName('DiD_Inventory').' didinv LEFT JOIN '.getTableName('Site_Inventory').' sididinv ON sididinv.site_key = didinv.site_key )  ON thn.topic_key = didinv.topic_key '
	},  # ------- User Credit Balance info can be gotten from here
	'SITEINVENTORY' => { 
		'columns' => {
			'site_name' => { from => '',to =>'' ,name => ' fsites01.current_site_name '},
			'owner' => { from => 'WT',to =>'Users' ,name => ' si1.owner_key '}
		}, 
		# the topic may or may not be a User Topic, so LEFT JOIN
		'joins' => ' LEFT JOIN ('.getTableName('Site_Inventory').' si1 INNER JOIN '.getTableName('Sites').' fsites01 ON si1.site_key = fsites01."key" ) ON thn.topic_key = si1.topic_key '
	},  # ------- User Site Inventory info can be gotten from here
	
	'TOPICINFOISA' => {
		'dotsql' => 'SELECT thisa."key" as thkey
			FROM '.getTableName('Topic_History').' thisa 
			DOTJOINS ',
		'dotcolumns' => {
			'user' => { from => '',to =>'' ,name => ' u1."key" IS NOT NULL ',
					'join' => ' INNER JOIN '.getTableName('Users').' u1 ON u1.user_topic_key = thisa.topic_key '},
			'group' => { from => '',to =>'' ,name => ' g1."key" IS NOT NULL ',
					'join' => ' INNER JOIN '.getTableName('Gropus').' g1 ON g1.group_topic_key = thisa.topic_key '},
			'account' => { from => '',to =>'' ,name => ' sac.accounts_key IS NOT NULL ',
					'join' => ' INNER JOIN '.getTableName('Splits').' sacc ON sacc.accounts_key = thisa.topic_key '},
			'transaction' => { from => '',to =>'' ,name => ' stx.transaction_key IS NOT NULL ',
					'join' => ' INNER JOIN '.getTableName('Splits').' stx ON stx.transaction_key = thisa.topic_key '}
		}
	}  # ------- This is for TOPICINFO.isA = user, which has a different structure to other queries

	
};
 
# not all Fields can be put in Order, so we have to manually select which fields can be put in the order field
my $OrderAlias = {
	'topic' => ' tname."value" ASC ',
	'created' => undef,
	# if modified, we want the most recent
	'modified' => ' thn.timestamp_epoch DESC ',
	'editby' => undef,
	
	# extra stuff not included in Foswiki
	'callsec' => 'cdr.billsec ASC ',
	'answertime' => 'cdr.answer_epoch ASC ',
	'source_number' => 'cdr.source_number ASC ',
	'destination_number' => 'cdr.destination_number ASC '	
};

sub getHoistAliasColumns {
	my $root = shift;
	my $column = shift;
	my $op = shift;
	my $table_number = shift;
	# the first two returns only deal with Blob_Store issues
	my $return_name = '';
	if( $op eq '~'){
		$return_name = 'word_name';
	}
	elsif(($op eq '>' || $op eq '<') && $HoistAlias->{$root}->{'columns'}->{$column}->{number_name}){
		$return_name = 'number_name';
	}
	else{
		$return_name = 'name';
	}
	my $return_column = $HoistAlias->{$root}->{'columns'}->{$column}->{$return_name};
	
	# need to search and replace all of the table names if there is a table number (_NUMBER)
	my @tables = split(',',$HoistAlias->{$root}->{'multiple'});
	if($table_number && $HoistAlias->{$root}->{'multiple'}){
		foreach my $t1 (@tables){
			my $replacement_string = $t1.'_'.$table_number;
			$return_column =~ s/$t1/$replacement_string/g;
		}
	}
	
	return $return_column;	
}

sub getHoistAliasColumnConvert {
	my $root = shift;
	my $column = shift;
	my $operation = shift;
	return ($HoistAlias->{$root}->{'columns'}->{$column}->{from},$HoistAlias->{$root}->{'columns'}->{$column}->{to});
}
sub getHoistAliasJoins {
	my $root = shift;
	my $table_number = shift;
	# normally, this is returned, except when there is a _NUMBER
	my $return_join = $HoistAlias->{$root}->{'joins'};
	
	# need to search and replace all of the table names if there is a table number (_NUMBER)
	my @tables = split(',',$HoistAlias->{$root}->{'multiple'});
	if($table_number && $HoistAlias->{$root}->{'multiple'}){
		foreach my $t1 (@tables){
			my $replacement_string = $t1.'_'.$table_number;
			$return_join =~ s/$t1/$replacement_string/g;
		}
	}
	return $return_join;
}

sub getOrderAlias {
	my $orderTerm = shift;
	return $OrderAlias->{$orderTerm};
}

sub getAlias {

	return $HoistAlias;
}

# Implements Foswiki::Store::Interfaces::QueryAlgorithm
sub query {
	my ( $query, $inputTopicSet, $session, $options ) = @_;

	my $topic_handler = Foswiki::Contrib::DBIStoreContrib::TopicHandler::->new();
	my $site_key = $topic_handler->{site_key};
	# set Webs="Main" option in the query #
	my @webNames = split(',',$options->{web}) if $options->{web};
	@webNames = () unless $options->{web};
	my @webKeys = ();
	foreach my $webN (@webNames){
		next if $webN eq 'all';
		push(@webKeys,$topic_handler->getWebKey($webN));
	}
	@webKeys = () if $options->{web} eq 'all';

	$query->{web_key} = \@webKeys unless scalar(@webKeys) == 0;
    
	# check to see if the topic history is also being searched
	$query->{history} = $options->{history};
    
	my ($SQLstring,$placeHolders) = Foswiki::Contrib::DBIStoreContrib::HoistSQL::hoist($query);
	

	my @crap = @$placeHolders;

	my $Webs = $topic_handler->getTableName('Webs');
	my $BS = $topic_handler->getTableName('Blob_Store');
	my $Topics = $topic_handler->getTableName('Topics');
	my $TH = $topic_handler->getTableName('Topic_History');

	my $fromWhereClause = qq{
SELECT thn."key", thn.topic_key, thn.revision,
thn.timestamp_epoch, thn.web_key, tname."value" as topic_name, 1 as summary,
webs.current_web_name as web_name, thn.user_key,
1 as deny, 1 as allow, thn.topic_content as topic_content_key,thn.topic_name as topic_name_key 
FROM
$TH thn 
	INNER JOIN ( $SQLstring ) as results ON thn."key" = results.thkey

	INNER JOIN $Webs webs ON thn.web_key = webs."key"
	INNER JOIN $BS tname ON thn.topic_name = tname."key"
	INNER JOIN $Topics tn ON thn."key" = tn.link_to_latest
WHERE 
 webs.site_key = ? WEBLIMIT

GROUP BY thn."key", thn.topic_key, thn.revision,
thn.timestamp_epoch, thn.web_key, tname."value",
webs.current_web_name, thn.user_key, thn.topic_content,thn.topic_name

};# we need one additional placeholder
	
	# Make sure this select is the same as the other select in Word Search
	my $selectClause = qq/SELECT DISTINCT thn."key", thn.topic_key, thn.revision,
		thn.timestamp_epoch, thn.web_key, tname."value" as topic_name, 1 as summary,
		webs.current_web_name as web_name, thn.user_key,
		mph_deny."value" as deny, mph_allow."value" as allow, thn.topic_content as topic_content_key,thn.topic_name as topic_name_key /;

	# generate an Order by statement
	# Order clause #

	my $orderByS = $options->{order};
	my @orderS = split(',',$orderByS) if $orderByS;
	@orderS = () unless $orderByS;
	my @subFinalOrderTerms = (' webs.current_web_name ASC ','  tname."value" ASC ');
	my @FinalOrderTerms;
	foreach my $orderTerm (@orderS){
		push(@FinalOrderTerms,getOrderAlias($orderTerm)) if getOrderAlias($orderTerm);
	}
	push(@FinalOrderTerms,@subFinalOrderTerms);
	my $orderBy = ' ORDER BY '.join(',',@FinalOrderTerms).' ';
	

	# LIMIT Clause #
	#my $limitBy = " ";
	my $limit = $options->{limit};
	my $limitBy = " ";
	if($limit){
		$limit =~ s/,//;
		$limit =~ s/\.//;
		if($limit =~m/([0-9]+)/i){
			$limit = $1;
		}
		else{
			$limit = undef;
		}
		$limitBy = " LIMIT $limit " if defined $limit && $limit ne 'all';
	}

	my $selectStatement = "$fromWhereClause  \n $orderBy \n $limitBy";

	# need to make sure we are only searching the correct web
	my @realwebkeys;
	foreach my $webK (@webKeys){
		push(@realwebkeys,qq{ webs."key" = '$webK' });
	}
	my $weblimit = join( ' AND ', @realwebkeys );

	if(scalar(@webKeys) > 0){
		$selectStatement =~ s/WEBLIMIT/ AND ($weblimit)/g;
	}
	else{
		$selectStatement =~ s/WEBLIMIT//g;
	}	

	my $searchHandler = $topic_handler->database_connection()->prepare($selectStatement);
	my @temp = @crap;
	push(@crap,$site_key);
	#my $crap = join('|',@crap);
	#die "SQL:\n$selectStatement\n|$crap|";
	#die "Statement:\n$selectStatement\n\n$crap";
	my $arrayReturn_ref;
	
	# put searchHandler in an eval.
	eval{
		#die "SQL: $selectStatement\n\n\n@crap";
		$searchHandler->execute(@crap);
		
		$arrayReturn_ref = $searchHandler->fetchall_arrayref;
		$topic_handler->database_connection()->commit;
	};

	if ($@) {
		die "Didn't work.  (".$@.")";
		$topic_handler->database_connection()->errstr;
		eval{
			$topic_handler->database_connection()->rollback;
		};
	}
	return Foswiki::Contrib::DBIStoreContrib::ResultSet->new($arrayReturn_ref );
		
}




1;

__END__
