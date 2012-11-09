# Package: AppCore::DBI
# Core DBI routines for EAS, designed to be used as a root for Class::DBI-extended objects. Provides stringification and meta-data routines. 
# Can be used in combination with AppCore::Common mysql_update_schema() to automatically store database schema with the object itself. 

use strict;
	
package AppCore::DBI;
{
	use base qw(Class::DBI);
	
	
	our @PriKeyAttrs = (
		'extra'	=> 'auto_increment',
		'type'	=> 'int(11)',
		'key'	=> 'PRI',
		readonly=> 1,
		auto	=> 1,
	);
	
	use strict;
	use Class::DBI;
	use AppCore::Common;
	#use AppCore::PersistantUserPref;
	
	
	sub DEFAULT_DB()   { AppCore::Config->get("DB_NAME") || 'appcore'}
	sub DEFAULT_HOST() { AppCore::Config->get("DB_HOST") || 'localhost' };
	sub DEFAULT_USER() { AppCore::Config->get("DB_USER") || 'root'};
	sub DEFAULT_PASS() { AppCore::Config->get("DB_PASS") || '' };
	
	
	# Required for Class::DBI compat
	our %DBI_ATTRS = (
			RaiseError         => 1,
			PrintError         => 0,
			Taint              => 1,
			RootClass          => 'DBIx::ContextualFetch',
			FetchHashKeyName   => 'NAME_lc',
			ShowErrorStatement => 1,
			ChopBlanks         => 1,
			AutoCommit         => 1
	);
	# Get Class::DBI's default dbh options
	#our %DBI_ATTRS = __PACKAGE__->_default_attributes;
	
	# For Class::DBI compatibility
	#sub db_Main{__PACKAGE__->dbh(DEFAULT_DB,DEFAULT_HOST,DEFAULT_USER,DEFAULT_PASS,%DBI_ATTRS)}
	#__PACKAGE__->_remember_handle('Main');
	
	__PACKAGE__->_remember_handle('Main'); # so dbi_commit works
	
	sub _croak
	{
		AppCore::Common::print_stack_trace(0);
		print STDERR $_[1], "\n";
		shift->SUPER::_croak(@_);
	}
	
	my %DBPARAMS_CLASS_CACHE;
	
	# override default to avoid using Ima::DBI closure
	sub db_Main 
	{
		my $class = shift;
		
		$class = ref $class if ref $class;
			
		my $dbh;
		
		#print STDERR "Debug: $class->db_Main()\n";
		
		if ( !$dbh ) 
		{
			#print STDERR __PACKAGE__."::db_Main(): class:'$class', DBPARAMS CACHE = ".Dumper($DBPARAMS_CLASS_CACHE{$class});
			$dbh = $class->dbh($DBPARAMS_CLASS_CACHE{$class}->{DEFAULT_DB}   || DEFAULT_DB,
					$DBPARAMS_CLASS_CACHE{$class}->{DEFAULT_HOST} || DEFAULT_HOST,
					$DBPARAMS_CLASS_CACHE{$class}->{DEFAULT_USER} || DEFAULT_USER,
					$DBPARAMS_CLASS_CACHE{$class}->{DEFAULT_PASS} || DEFAULT_PASS,
					%DBI_ATTRS);
# 			if ( $ENV{'MOD_PERL'} and !$Apache::ServerStarting ) 
# 			{
# 				Apache2::RequestUtil->request->pnotes( $key, $dbh );
# 			}
# 			elsif(AppCore::Common->context->{httpd})
# 			{
# 				$dbh = AppCore::Common->context->{httpd}->_context->{dbh_cache}->{$key} = $dbh;
# 			}
		}
		
		
		#print STDERR "class=$class, dbh=$dbh ($dbh->{Name})\n";
		
		return $dbh;
	}
	
	sub setup_default_dbparams
	{
		my $class = shift;
		$class = ref $class if ref $class;
		#print STDERR __PACKAGE__."::setup_default_dbparams(): class:'$class', args: ".join('|', @_)."\n";
		$DBPARAMS_CLASS_CACHE{$class} = 
		{
			DEFAULT_DB   => shift,
			DEFAULT_HOST => shift,
			DEFAULT_USER => shift,
			DEFAULT_PASS => shift,
		};
	}
	
	my %META_CACHE;
	sub meta
	{
		my $class = shift;
		my $meta = shift;
		
		#die Dumper $class if !$meta;
		
		# Use the package name as the key, not an object ref address
		$class = ref $class if ref $class;
		
		#print STDERR "Debug: $class->meta(): at start, table=".$class->table."\n";
		
		if(defined $meta && ref $meta eq 'HASH')
		{
			# If given a hashref for meta, store it in the cache against this classname
			$META_CACHE{$class} = $meta;
			
			
			#print STDERR __PACKAGE__."::meta(): class:'$class', db:'$meta->{db}'\n";
			
			# Setup AppCore::DBI db_Main parameters
			if($meta->{database} || $meta->{db})
			{
				$meta->{database} ||= $meta->{db};
				#print STDERR __PACKAGE__."::meta(): class:'$class', calling setup dbparams, other args: host:'$meta->{db_host}',user:'$meta->{db_user}',pass: ***\n";
				$class->setup_default_dbparams($meta->{database},$meta->{db_host},$meta->{db_user},$meta->{db_pass});
			}
			
			# Setup AppCore::DBI aliasing of the class->table and the CDBI table name
			if($meta->{table})
			{
				my $table = $meta->{table};
				#AppCore::DBI->table_to_class_alias($table,$class);
		
				#print STDERR "Debug: setting $class->table to '$table'\n";
				$class->table($table);
			}
			
			
		}
		
		$meta = $META_CACHE{$class};
		
		# If no meta specified yet, create our own meta
		if(!$meta)
		{
			
			$meta = 
			{
				
			};
			
			$META_CACHE{$class} = $meta;
		}
		
		# Do the auditing only once. 
		# We audit here instead of inside the "if(!$meta)" block above, so that 
		# we audit both the auto-created meta and the package-specified meta.
		if(!$meta->{_audited})
		{
			my $table = AppCore::Common::guess_title($class->table);
			#$table =~ s/^(\w)(.*)$/uc($1).$2/segi;
		
			my $table_noun = $table;
			$table_noun =~ s/([^aeiou])s$/$1/g;
			
			my $db = $meta->{db} || $meta->{database};
			if(!$db)
			{
				my $dsn = $class->db_Main->{Name};
				$dsn =~ /database=([^;]+)/;
				$db = $1;
				
				$meta->{db} = $meta->{database} = $db;
			}
			
			if(!$meta->{class_noun})
			{
				$meta->{class_noun} = $table_noun;
			}
			
			if(!$meta->{class_title})
			{
				$meta->{class_title} = AppCore::Common::guess_title($class->table);
			}
			
			# Load the schema from MySQL if none specified
			if(!$meta->{schema})
			{
				#print STDERR "No schema for $class: ".Dumper($meta);
				my $dbh = $class->db_Main;
				my @list;
				my $sth = $dbh->prepare_cached('explain '.$dbh->quote_identifier($class->table),undef,1);
				$sth->execute;
				while(my $ref = $sth->fetchrow_hashref)
				{
					$ref->{lc $_} = $ref->{$_} foreach keys %$ref;
					push @list, $ref;
				}
				$sth->finish;
				#print STDERR "Audited Schema: ".Dumper(\@list);
		
				$meta->{schema} = \@list;
				$meta->{_auto_schema} = 1;
			}
			
			# Grab the schema for usein creating the next set of fields
			my @s = @{ $meta->{schema} || [] };
			
			my @columns = $class->columns;
			if(@s && !@columns)
			{
				# Setup Class::DBI column group 'All'
				my @columns = map { $_->{field} } @s;
				$class->columns(All => @columns) if @columns;
				$class->columns(Essential => @columns) if @columns;
				
				
				# Create CDBI relationships using meta 'linked' field
				foreach my $line (@{$meta->{schema}})
				{
					$class->has_a($line->{field} => $line->{linked}) if $line->{linked};
				}
			}
			
			if(@s)
			{
				foreach my $line (@s)
				{
					$line->{title} = AppCore::Common::guess_title($line->{field}) if !$line->{title};
				}
			}
			
			
			# table_list is used by AppCore::BlueDB for creation of List screens
			if(!$meta->{table_list})
			{
				$meta->{table_list} = [ map{$_->{field}} @s ];
			}
			
			# filter_list is used by AppCore::BlueDB as a list of search fields
			if(!$meta->{filter_list})
			{
				$meta->{filter_list} = $meta->{table_list};
			}
			
			# edit_list is used by AppCore::BlueDB for edit screens - note that 
			# the list of fields in edit_list can be split by pipes (|) to indicate <hr>'s in the form
			if(!$meta->{edit_list})
			{
				$meta->{edit_list} = [ map{$_->{field}} @s ];
				$meta->{_auto_edit_list} = 1;
			}
			
			# TBD - rethink this and the stringify stuff
			if(!$meta->{sort})
			{
				my $s;
				foreach my $f (@s)
				{
					if($f->{type}=~/varchar/)
					{
						$s = $f;
						last;
					}
				}
				$meta->{first_string} = $s->{field} if $s;
				#print STDERR "$class: first_string=$meta->{first_string}\n";
				
				$meta->{sort} = $s->{field} if $s;
			}
			
			# field_map is used by AppCore::DBI stringify functions for looking up field properties.
			# Can be used thru $self->field_meta($col)
			if(!$meta->{field_map})
			{
				$meta->{field_map} = { map { lc $_->{field} => $_ } @s };
			}
			
			# Prevents re-audits on each meta() call
			$meta->{_audited} = 1;
		}
		
		return $meta;
	}
	
	
	sub field_meta
	{
		my $self = shift;
		my $col = shift;
		return $self->meta->{field_map}->{lc $col};
	}
	
	use Data::Dumper;
	
	sub hashref_copy
	{
		my $self = shift;
		my @cols = @_;
		@cols = map { $_->{field} } @{$self->meta->{schema}} if !@cols;
		return {} if !@cols;
		#print STDERR Dumper( \@cols );
		return { map { $_ => $self->get($_) } @cols };
	}
	
	
	sub stringify
	{
		my $class = shift;
		my $id = shift;
		
		# Shouldn't break anything since we don't want to proceede if we don't have the actual record
		my $record = ref $class ? $class : undef;
		
		#print STDERR "$class->stringify: id=[$id] (ref id? ".ref($id).")\n";
		$record = ref $id ? $id : $class->retrieve($id) if defined $id;
		#if($id && !defined $record)
		#{
			#$record = $class->retrieve($class->validate_string($id));
		#}
		
		return '' if !defined $id && !ref $record && !defined $record;
		
		#print STDERR "Got record: $record (".ref($record).")\n"; #, recordid=[".($record?$record->id:"")."]\n";
		
		if(!$record)
		{
			#warn "No record defined: class=$class, id=[$id] (".ref($id).")\n";
			return '';
		}
		
		my @fmt  = $record->can('stringify_fmt') ? $record->stringify_fmt : ();
		@fmt = ('#'.($record->meta->{first_string} || $record->primary_column)) if !@fmt;
		#die Dumper \@fmt;
		return $record->_exec_string_fmt(\@fmt);
	}
	
	sub _exec_string_fmt
	{
		my $self = shift;
		my $fmt = shift || [];
		
		my @buf;
		foreach my $val (@$fmt)
		{
			# If $val is an array, assume that its in an ABC format - 
			#  - A is the "if" column - basically, value of that column must evaulate to perl boolean true (not null, not empty string, not zero, not a zero date)
			#  - B is the "positive" outcome, in the same format as the stringify fmt itself (can be recursive IFs as well)
			#  - C is the "negative" outcome
			if(ref $val eq 'ARRAY')
			{
				my ($col,$is_good,$is_bad) = @$val;
				$col =~ s/^#//g;
				$val = $self->get($col);
				#die Dumper $val if ref $val;
				undef $val if ref $val && !$val->id;
				if(!$val || $val eq '0000-00-00 00:00:00')
				{
					$is_bad = []  if !$is_bad || ref $is_bad ne 'ARRAY';
					$val = $self->_exec_string_fmt($is_bad);
				}
				else
				{
					$is_good = [] if !$is_good || ref $is_good ne 'ARRAY';
					$val = $self->_exec_string_fmt($is_good);
				}
			}
			# Column references start with a hash, so to reference column 'title', use '#title'
			elsif($val =~ /^#(.+)$/)
			{
				eval
				{
					$val = $self->get($1);
					$val = $val->stringify if ref $val && eval '$val->can("stringify")';
				};
				if($@)
				{
					die "Error while stringifying ".ref($self)."#$self, field name '$1': $@";
				}
			}
			# All other $val's are interpreted to be literal strings
	
			push @buf, $val;
		}
		
		return join '', @buf;
	}
	
	
	sub get_orderby_sql
	{
		my $class = shift;
		my $args = shift;
		my $dbh = $class->db_Main;
		
		my $s = $class->meta->{sort};
		
		
		if(ref $args eq 'HASH' && $args->{sort})
		{
			# Added to support integration with Ext 2.2 JSON reader / BlueDB screen_list {json_list}
			$s = [[$args->{sort},lc $args->{dir}]];
		}
		elsif(ref $args eq 'ARRAY')
		{
			$s = $args;
		}
		else
		{
			$s = [$s] if ref $s ne 'ARRAY';
			$s = [$class->meta->{first_string}] if !@$s;
			
	# 		my $user_sort = AppCore::PersistantUserPref->get_pref(join('/',$class,'sort'));
	# 		if($user_sort)
	# 		{
	# 			my @list = split /\s*,\s*/, $user_sort;
	# 			my @tmp;
	# 			foreach my $x (@list)
	# 			{
	# 				my @y = split /\s+/, $x;
	# 				push @tmp, @y > 1 ? \@y : shift @y;
	# 			}
	# 			
	# 			$s = \@tmp;
	# 		}
			#$table_list = [split(',',$user_cols)] if $user_cols;
		}
		
		my @order;
		foreach my $col (@$s)
		{
			if(ref $col eq 'ARRAY')
			{
				my ($field,$dir) = @$col;
				$dir = lc $dir eq 'desc' ? 'DESC' : 'ASC';
				push @order, $dbh->quote_identifier($field).' '.$dir;
			}
			else
			{
				push @order, $dbh->quote_identifier($col);
			}
		}
		
		#die Dumper \@order;
		
		return @order ? join ', ', @order : undef;
	}
	
	
	sub get_stringify_sql
	{
		my $self = shift;
		my $lower_case = shift || 0;
		my $depth = shift || 0;
		my @fmt  = $self->can('stringify_fmt') ? $self->stringify_fmt : ();
		@fmt = ('#'.($self->meta->{first_string} || $self->primary_column)) if !@fmt;
		
		return $self->_create_string_sql(\@fmt,$lower_case,$depth);
	}
	
	use constant MAX_SQL_STRINGIFY_DEPTH => 1;
	
	sub _create_string_sql
	{
		my $self  = shift;
		my $fmt   = shift || [];
		my $lower_case = shift || 0;
		my $depth = shift || 0;  # guards against recursive stringification
		
		# Buffer for final SQL
		my @buf;
		
		my $dbh = $self->db_Main;
		
		my $db = $self->meta->{db} || $self->meta->{database};
		if(!$db)
		{
			my $dsn = $dbh->{Name};
			$dsn =~ /database=([^;]+)/;
			$db = $1;
			#die Dumper $db,$dsn;
		}
		$db = $dbh->quote_identifier($db);
		
		my $self_table = $dbh->quote_identifier($self->table);
					
		foreach my $val (@$fmt)
		{
			# If $val is an array, assume that its in an [A,B,C] format - 
			#  - A is the "if" column - basically, value of that column must evaulate to perl boolean true (not null, not empty string, not zero, not a zero date)
			#  - B is the "positive" outcome, in the same format as the stringify fmt itself (can be recursive IFs as well)
			#  - C is the "negative" outcome
			if(ref $val eq 'ARRAY')
			{
				my ($col,$is_good,$is_bad) = @$val;
				$col =~ s/^#//g;
				
				
				my $self_table = $dbh->quote_identifier($self->table);
					
				my $condition = "$db.$self_table.".$dbh->quote_identifier($col);
				
				# The truth of a foreign key is not only if its a non-zero integer, but also
				# if that foreign object exists - hence this subquery as the condition.
				my $x = $self->field_meta($col);
				if ($x->{linked} && eval '$x->{linked}->can("table")')
				{
					my $meta = eval '$x->{linked}->meta';
					if(!$meta || !$meta->{db} || !$meta->{database})
					{
						my $dsn = $x->{linked}->db_Main->{Name};
						$dsn =~ /database=([^;]+)/;
						$meta->{db} = $1;
						#die Dumper $meta,$dsn;
					}
					
					my $other_db   = $dbh->quote_identifier($meta->{db} || $meta->{database});
					my $table      = $dbh->quote_identifier($x->{linked}->table);
					my $primary    = $dbh->quote_identifier($x->{linked}->primary_column);
					my $self_field = $dbh->quote_identifier($x->{field});
					$condition = "(SELECT COUNT($other_db.$table.$primary) FROM $other_db.$table WHERE $other_db.$table.$primary=$db.$self_table.$self_field) = 1";
				}
				elsif($x->{type} =~ /varchar/)
				{
					$condition = "$condition <> '' AND $condition IS NOT NULL";
				}
				
				
				$is_good = [] if !$is_good || ref $is_good ne 'ARRAY';
				$is_bad  = [] if !$is_bad  || ref $is_bad  ne 'ARRAY';
				
				push @buf, join '', 'IF(', $condition, ',', $self->_create_string_sql($is_good,$lower_case), ',', $self->_create_string_sql($is_bad,$lower_case), ')';
				
			}
			# Column references start with a hash, so to reference column 'title', use '#title'
			elsif($val =~ /^#(.+)$/)
			{
				my $col = $1;
				my $x = $self->field_meta($col);
				if ($x->{linked} && eval '$x->{linked}->can("get_stringify_sql")' && $depth < MAX_SQL_STRINGIFY_DEPTH)
				{
					my $concat     = $x->{linked}->get_stringify_sql($lower_case,$depth+1);
					
					my $meta = eval '$x->{linked}->meta';
					#die Dumper $meta if $x->{linked} =~ /Auth/;
					if(!$meta || !$meta->{db} || !$meta->{database})
					{
						my $dsn = $x->{linked}->db_Main->{Name};
						$dsn =~ /database=([^;]+)/;
						$meta->{db} = $1;
						#die Dumper $meta,$dsn;
					}
					
					my $other_db   = $dbh->quote_identifier($meta->{db} || $meta->{database});
					
					my $table      = $dbh->quote_identifier($x->{linked}->table);
					my $primary    = $dbh->quote_identifier($x->{linked}->primary_column);
					my $self_field = $dbh->quote_identifier($x->{field});
					
					# In testing the sub-select on MySQL on my WinXP laptop, I've found that CONCAT('x',NULL) = NULL,
					# whereas I would expect a similar behaviour to perl, in that 'x'.undef eq 'x'. So, to accomidate
					# for CONCAT's behaviour, I first have to check that a subselect would actually give any results
					# for this query, hence the count() as the truth test for the if() function. If more or less than 
					# one result exists, the IF() will return an empty string instead of a null. The reason I don't let
					# more than one result thru (e.g. check count()=1) is because MySQL throws an error if more than one
					# row comes back from a subquery, saying something like "subquery returns more than one row" or something like that.
					
					push @buf, join '', "IF(",
								"(SELECT COUNT($other_db.$table.$primary) FROM $other_db.$table WHERE $other_db.$table.$primary=$self_table.$self_field) = 1,",
								"(SELECT $concat FROM $other_db.$table WHERE $other_db.$table.$primary=$db.$self_table.$self_field),",
							"'')";
				}
				else
				{
					my $ident = $dbh->quote_identifier($col);
					push @buf, $lower_case ? "LOWER($db.$self_table.$ident)" : "$db.$self_table.$ident";
				}
			}
			# All other $val's are interpreted to be literal strings
			else
			{
				#print STDERR "Debug: case3: val=[$val]\n";
				my $val = $dbh->quote($val);
				push @buf, $lower_case ? lc $val : $val;
			}
		}
		
		
		#@buf = '""' if !@buf;
		
		return @buf ? (@buf == 1 ? shift @buf : 'CONCAT('.join (',', @buf).')' ) : '""';
	}
	
	sub get_stringify_regex
	{
		my $self = shift;
		my $index = shift || 0;
		my $depth = shift || 0;
		my @fmt  = $self->can('stringify_fmt') ? $self->stringify_fmt : ();
		@fmt = ('#'.($self->meta->{first_string} || $self->primary_column)) if !@fmt;
	
	#	if(@fmt == 3 && $fmt[2] == ' ')
	#	{
	#		my ($rx1,$tag1) = $self->_create_string_regex([$fmt[0]],$index,$depth);
	#		my ($rx2,$tag2) = $self->_create_string_regex([$fmt[1]],$index,$depth,{pat_required=>1});
	#		my ($rx3,$tag3) = $self->_create_string_regex([$fmt[2]],$index,$depth,{greedy=>1});
	#		
	#		return (join('',$rx1,$rx2,$rx3),[$tag1,$tag2,$tag3]);
	#	}
		
		return $self->_create_string_regex(\@fmt,$index,$depth);
	}
	
	sub _create_string_regex
	{
		my $self  = shift;
		my $fmt   = shift || [];
		my $index = shift || 0;
		my $depth = shift || 0;  # guards against recursive stringification
		my $opts = shift;
		# If we're inside a conditional, the first field must not be 'optional' ...
		
		# Buffer for final regex
		my @buf;
		my @field_tags;
		
		my $index_consumed = 0;
		
		my $dbh = $self->db_Main;
		foreach my $val (@$fmt)
		{
			$index_consumed = 1;
			# If $val is an array, assume that its in an [A,B,C] format - 
			#  - A is the "if" column - basically, value of that column must evaulate to perl boolean true (not null, not empty string, not zero, not a zero date)
			#  - B is the "positive" outcome, in the same format as the stringify fmt itself (can be recursive IFs as well)
			#  - C is the "negative" outcome
			if(ref $val eq 'ARRAY')
			{
				my ($col,$is_good,$is_bad) = @$val;
				$col =~ s/^#//g;
				
				$is_good = [] if !$is_good || ref $is_good ne 'ARRAY';
				$is_bad  = [] if !$is_bad  || ref $is_bad  ne 'ARRAY';
				my $i_start = $index;
				my ($good_re,$good_tags, $i2) = $self->_create_string_regex($is_good,$index,$depth,{inside_conditional=>1});
				my ($bad_re, $bad_tags,  $i3) = $self->_create_string_regex($is_bad, $i2,   $depth,{inside_conditional=>1});
				$index = $i3;
				my $i_end = $i3 - 1;
				
				
				push @buf, join '', '(?:', $good_re , '|', $bad_re , ')';
				
				push @field_tags, {type=>'if', range=>1, index_start=>$i_start, index_end=>$i_end };
				#, tags=>[$good_tags,$bad_tags] 
				push @field_tags, @$good_tags;
				push @field_tags, @$bad_tags;
				$index_consumed = 0;
				
			}
			# Column references start with a hash, so to reference column 'title', use '#title'
			elsif($val =~ /^#(.+)$/)
			{
				my $col = $1;
				my $x = $self->field_meta($col);
				if ($x->{linked} && eval '$x->{linked}->can("get_stringify_sql")' && $depth < MAX_SQL_STRINGIFY_DEPTH)
				{
					my $i_start = $index;
					my ($re,$tags,$i2) = $x->{linked}->get_stringify_regex($index,$depth+1);
					my $i_end = $index = $i2;
					push @buf, $re;
					# tags=>$tags,
					push @field_tags, { type=>'linked', range=>1, linked=>1, field=>$col, meta=>$x, index_start=>$i_start, index_end=>$i_end  };
					push @field_tags, @$tags;
					$index_consumed = 0;
				}
				else
				{
					my $pat = $x->{type} =~ /int/i        ? '[+-]?\d+' :
						$x->{type} =~ /float/i      ? '[+-]?(?:\d+)\.?(?:\d+)' :
						$x->{type} =~ /datetime/i   ? '\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}' :
						$x->{type} =~ /date/i       ? '\d{4}-\d{2}-\d{2}' :
						$x->{type} =~ /time/i       ? '\d{2}:\d{2}:\d{2}' :
						$x->{type} =~ /varchar/i    ? (
							$x->{string_fmt_hint} =~ /word/  ? '\w+' :
							$x->{string_fmt_hint} =~ /phone/ ? '(?:\(?\d\d\d\)?)?(?: |-|\.)?\d\d\d(?: |-|\.)?\d{4,4}(?:(?: |-|\.)?[ext\.]+ ?\d+)?' :
							$x->{string_fmt_hint} =~ /email/ ? '[\w-\.]+@(?:[\w-]+\.)+[\w-]{2,4}' :
							
							'.+' . ($opts->{greedy} ? '' : '?')
						) :
						'.+' . ($opts->{greedy} ? '' : '?');
					
					push @buf, "($pat)" . ($opts->{pat_required} || $opts->{inside_conditional} ? '' : '?');
					$opts->{inside_conditional} = 0 if $opts->{inside_conditional}; # only the first field in the conditional needs to not be optional
					
					push @field_tags, {type=>'field',field=>$col, meta=>$x, index=>$index};
				}
			}
			# All other $val's are interpreted to be literal strings
			else
			{
				#print STDERR "Debug: case3: val=[$val]\n";
				my $oval = $val;
				$val =~ s/([\+\(\)\[\]\.\^\$])/\\$1/g;
				push @buf, "($val)" . ($opts->{inside_conditional} ? '' : '?');
				$opts->{inside_conditional} = 0 if $opts->{inside_conditional}; # only the first field in the conditional needs to not be optional
				
				push @field_tags, {type=>'literal',value=>$oval, index=>$index };
			}
			$index ++ if $index_consumed;
			
		}
		
		
		#@buf = '""' if !@buf;
		
		return ( join ('', @buf) , \@field_tags, $index );
	}
	
	sub get_stringified_fields
	{	
		my $class = shift;
		my $val = shift;
		
		my $debug = shift || 0;
		
		my ($regexp,$fields,$index_count) = $class->get_stringify_regex();
		print "$class->get_stringified_fields($val): Regex: $regexp\n" if $debug;
		my @match = $val =~ /^$regexp$/;
		#print Dumper [ $val, @match ], $fields,$index_count;
		
		@match = ($val) if !@match;
		
		my $depth = 0;
		my $depth_end = undef;
		foreach my $tag (@$fields)
		{
			my $tabs = "   " x $depth;
			if($tag->{range})
			{
				$depth ++;
				$depth_end = $tag->{index_end};
			}
			else
			{
				$depth -- if defined $depth_end && $depth_end == $tag->{index};
				
				if($tag->{index} > $#match)
				{
					#AppCore::Common::print_stack_trace(0);
					#die "Index out of range for tag: ".Dumper($tag);
					last;
				}
				
				my $x = $match[$tag->{index}];
				$x =~ s/(^\s+|\s+$)//g;
				
				my $name = $tag->{type} eq 'literal' ? '(literal)' : '#'.$tag->{field};
				print STDERR "[Regex Match Dump] $tabs $tag->{index}: $name:\t ".(defined $x?"'$x'":'undef')."\n" if $debug;
				
			}
		}
		
		
		
		my @out;
		my %tags_consumed;		
		
		foreach my $tag (@$fields)
		{
			#print STDERR "Processing col ".$col->dbcolumn.", part=[$part], x=$x, \$list[$x]=$list[$x]\n";
			next if $tag->{type} eq 'literal' || $tags_consumed{$tag->{index}};
			
			#print "c:".ref($c)."\n";
			#print STDERR "Processing tag $tag->{type}: $tag->{field}\n";
			if($tag->{linked})
			{
				#print STDERR "\$col->dbcolunmn=".$col->dbcolumn.", \$c->dbcolumn=".$c->dbcolumn.", foreignkey='yes' for \$c\n";
				my @buf;
				
				#die Dumper $tag;
				
				for my $x ($tag->{index_start} .. $tag->{index_end})
				{
					$tags_consumed{$x} = 1;
					push @buf, $match[$x];
				}
				
				#die Dumper \@buf;
				
				my $res = $tag->{meta}->{linked}->validate_string(join '', @buf);
				#if($res->{id})
				if($res && !$@)
				{
					push @out, [$tag->{field},$res] if $res;
				}
				#else
			}
			else
			{
				my $val = $match[$tag->{index}];
				$val =~ s/(^\s+|\s+$)//g;
				push @out, [$tag->{field},$val] if $val;
			}
		}	
		
		return @out;
	
	}
	
	# Returns a hash of field=>type pairs using type names expecteted by old PMS GenericTableColumn and PMS::DBI code
	sub _legacy_typehash
	{
		my $class = shift;
		my $meta = $class->meta;
		return $meta->{_legacy_typehash} if $meta->{_legacy_typehash};
		my @s = @{$meta->{schema} || []};
		my %hash;
		#Number','String','Text','PrimaryForeignKey','ForeignKey','ForeignKeyList','ACLList','EnumList','YesNo','DateTime','Date','SequenceNumber','AutoNumber','PrimaryKeyAutoNumber','TimeStamp','ImageDocumentID'
		foreach my $f (@s)
		{
			my $k = $f->{field};
			my $t = $f->{type};
			
			$t = $t =~ /varchar/i     ? 'String' :
			$t =~ /(int|float)/i ? 'Number' :
			$t =~ /datetime/i    ? 'DateTime' : 
			$t =~ /timestamp/i   ? 'TimeStamp' : 
			$t =~ /time/i        ? 'Time' :
			$t =~ /enum/i        ? 'EnumList' :
			'String';
			
			$hash{$k} = $hash{lc $k} = $t;
		}
		
		return $meta->{_legacy_typehash} = \%hash;
	}
	
	sub get_fkquery_sql
	{
		my $class = shift;
		my $val = shift;
		my $fkclause = shift || '1';
		
		my $debug = shift || 0;
		
		my $dbh = $class->db_Main;
		
		my $table = $class->table;
		my $pri = $class->primary_column;
		
		my $q_table = $dbh->quote_identifier($table);
		my $q_primary = $dbh->quote_identifier($pri);
		
		
		my ($regexp,$fields,$index_count) = $class->get_stringify_regex();
		print STDERR "$class->get_fkquery_sql($val): Regex: $regexp\n" if $debug;
		my @match = $val =~ /^$regexp$/;
		#print Dumper [ $val, @match ], $fields,$index_count;
		@match = ($val) if !@match;
		
		my $depth = 0;
		my $depth_end = undef;
		foreach my $tag (@$fields)
		{
			my $tabs = "   " x $depth;
			if($tag->{range})
			{
				$depth ++;
				$depth_end = $tag->{index_end};
			}
			else
			{
				$depth -- if defined $depth_end && $depth_end == $tag->{index};
				
				if($tag->{index} > $#match)
				{
					#AppCore::Common::print_stack_trace();
					#die "Index out of range for tag: ".Dumper($tag,\@match,$fields);
					last;
				}
				
				my $x = $match[$tag->{index}];
				$x =~ s/(^\s+|\s+$)//g;
				
				my $name = $tag->{type} eq 'literal' ? '(literal)' : '#'.$tag->{field};
				print STDERR "[Regex Match Dump] $tabs $tag->{index}: $name:\t ".(defined $x?"'$x'":'undef')."\n" if $debug;
				
			}
		}
		
		
		
		my %tags_consumed;	
		
		my $clause = '1';
		my @tables;
		my @args;
		
		foreach my $tag (@$fields)
		{
			#print STDERR "Processing col ".$col->dbcolumn.", part=[$part], x=$x, \$list[$x]=$list[$x]\n";
			next if $tag->{type} eq 'literal' || $tags_consumed{$tag->{index}};
			
			#print "c:".ref($c)."\n";
			#print STDERR "Processing tag $tag->{type}: $tag->{field}\n";
			if($tag->{linked})
			{
				#print STDERR "\$col->dbcolunmn=".$col->dbcolumn.", \$c->dbcolumn=".$c->dbcolumn.", foreignkey='yes' for \$c\n";
				my @buf;
				
				#die Dumper $tag;
				
				for my $x ($tag->{index_start} .. $tag->{index_end})
				{
					$tags_consumed{$x} = 1;
					push @buf, $match[$x];
				}
				
				#die Dumper \@buf;
				
				my $res = $tag->{meta}->{linked}->validate_string(join '', @buf);
				#if($res->{id})
				if($res && !$@)
				{
					$clause .= " and ".$dbh->quote_identifier($tag->{field})."=? ";
					push @args, $res; #->{id};
				}
				#else
			}
			else
			{
				my $val = $match[$tag->{index}];
				$val =~ s/(^\s+|\s+$)//g;
				my $inq = {$tag->{field}=>$val};
				#print Dumper $inq,$class->can('get_where_clause')?1:0,$class->can('compose_where_clause')?1:0;
				my ($tables,$cl,@args2) =       $class->can('get_where_clause')     ? $class->get_where_clause($inq,2) : 
								$class->can('compose_where_clause') ? $class->compose_where_clause($inq,$class->_legacy_typehash,undef,2) :
								(undef,$dbh->quote_identifier($tag->{field}).'=?',$val);
				
				#$clause .= " and lower(`".$c->dbcolumn."`) like ? ";
				$clause .= " and $cl";
				
				push @args, @args2;
				push @tables, $tables if $tables && $tables ne '';
			}
		}
		
		my $sql_suffix = '';
		
		if($class->meta->{sort} || $class->meta->{first_string})
		{
			$sql_suffix = "order by ".$class->get_orderby_sql;
		}
		
		
		my $fklookup_sql = $q_table.(@tables?', '.join(',',map {$dbh->quote_identifier($_)} @tables):'')." where $fkclause and $clause $sql_suffix";
		print STDERR "$class->get_fkquery_sql($val): fklookup_sql2: $fklookup_sql, args: [".join('|',@args)."]\n" if $debug;
		
		return ($fklookup_sql,@args);
	
	}
	
	
	# Return val is kinda wierd - a HASH ref, with either {id} set to the fk id, or {error} set to a message
	sub stringified_list
	{
		my $class = shift;
		
		my $dbh = $class->db_Main;
		
		my $table = $class->table;
		my $pri = $class->primary_column;
		
		my $val = shift;
		
		my $fkclause = shift || '1';
		$fkclause = '1' if $fkclause =~ /={{/;
		
		my $include_objects = shift || 0;
		
		my $start = shift;
		$start = -1 if !defined $start;
		my $limit = shift || -1;
		
		my $include_empty = shift || 0;
		
		my $debug = shift || 0;
		
		
		my $q_table = $dbh->quote_identifier($table);
		my $q_primary = $dbh->quote_identifier($pri);
		my ($fklookup_sql,@args) = $class->get_fkquery_sql($val,$fkclause,$debug);
		
		#print STDERR "\$include_empty='$include_empty'\n";
		unless ($include_empty)
		{
			
			my $text = $class->get_stringify_sql;
			$fklookup_sql =~ s/where/where ($text <> "") and/i;
			#print STDERR "after sub:
		}
						
		my $ob = $class->get_orderby_sql();
		my $list_sql = "select $q_primary as `id`, ".$class->get_stringify_sql." as `text` from ".$fklookup_sql;
		
		#print STDERR "Debug mark0: start=$start, limit=$limit\n";
		
		
				
		my $count = -1;
		if($start>-1 && $limit>-1)
		{
			#print STDERR "Debug mark1: start=$start, limit=$limit\n";
			$start =~ s/[^\d]//g;
			$limit =~ s/[^\d]//g;
			#print STDERR "Debug mark2: start=$start, limit=$limit\n";
			
			if(defined $start && defined $limit && $start ne '' && $limit ne '')
			{
				my $count_sql = "select count($q_primary) as `count`  from ".$fklookup_sql;
				my $sth = $dbh->prepare($count_sql);
				$sth->execute(@args);
				$count = $sth->fetchrow_hashref->{count};
			
				$list_sql .= " limit $start, $limit";
			}
		}
		
		print STDERR "$class->stringified_list($val): list_sql = $list_sql, args = (".join('|',@args).")\n" if $debug;
		
		my $sth = $dbh->prepare($list_sql);
		$sth->execute(@args);
		
		my @list;
		local $_;
		while(my $ref = $sth->fetchrow_hashref)
		{
			if($include_objects)
			{
				my $x = $class->retrieve($ref->{id});
				$ref->{instance} = $x;
				
				$x->{$_} = $x->get($_) foreach $x->columns;
			}
			push @list, $ref;
		}
		
		return $count > -1 ? {count=>$count,list=>\@list} : \@list;
	}
	
	# Returns the primary key of the validated record OR undefined and sets $@ to an error msg
	sub validate_string
	{
		my $class = shift;
		
		my $dbh = $class->db_Main;
		
		my $table = $class->table;
		my $pri = $class->primary_column;
		
		my $q_table = $dbh->quote_identifier($table);
		my $q_primary = $dbh->quote_identifier($pri);
					
		undef $@;
		undef $!;
		
		#print "mark1: $gentab\n";
		
		my $val = shift;
		
		my $fkclause = shift || '';
		
		my $multi_match = shift || 0;
		
		my $check_pri = shift;
		$check_pri = 1 if !defined $check_pri;
		
		my $adder = shift || 0; # Partial matching.. ?
		
		my $debug = shift || 0; 
		
		print STDERR "$class->validate_string($val): Start (fkclause=$fkclause, check_pri=$check_pri,multi_match=$multi_match,adder=$adder)\n" if $debug;
		
		if(!$val || $val eq '^(None/Any)' || $val eq '')
		{
			#return {id=>0,value=>'^(None/Any)'}; #$f->{fkd})};
			print STDERR "$class->validate_string($val): RETURN at [NULL] val\n" if $debug;
			#return {id=>0,value=>''}; #$f->{fkd})};
			$@ = undef;
			return ();
		}
		
		my @fmt  = $class->can('stringify_fmt') ? $class->stringify_fmt : ();
		@fmt = ('#'.$class->primary_column) if !@fmt;
		my @dbcols = map { s/^#//;$_ } grep { /^#/ } @fmt;
		if(!@dbcols && ref $fmt[0] eq 'ARRAY')
		{
			@dbcols = map { s/^#//;$_ } grep { /^#/ } @{$fmt[0]};
		}
		#die Dumper \@f;
		
		
		my $concat = $class->get_stringify_sql(1);
		
		
		$fkclause = '1' if !$fkclause || $fkclause eq '' || $fkclause =~ /={/;
		$fkclause = '('.$fkclause.')';
		
		my $sql = "select $q_primary from $q_table where $q_table.$q_primary = ? and $fkclause";
		#print "$class->validate_string($val): sql=$sql, val=[$val]\n";
		my $sth = $dbh->prepare($sql);
		
		
		my $field_diz = $class->field_meta($pri);
		my $type = $field_diz->{type};
		$check_pri = 0 if $type =~ /int/i && $val =~ /[^\d]/g;
		
		$sth->execute($val) if $check_pri;
		
		#print STDERR "Debug: check_pri=$check_pri\n";
		
		if($check_pri && $sth->rows)
		{
			my $f = $sth->fetchrow_hashref;
			#my $fkv = $class->stringify($f->{$pri});
			#print "$class->validate_string($val): pri=[$pri], f->{pri}=[$f->{$pri}], fkv=[$fkv]\n"; #,Dumper($f);
			print STDERR "$class->validate_string($val): RETURN at $q_primary is = $val\n" if $debug;
			#return {id=>$f->{$pri},value=>$fkv}; #$f->{fkd})};
			my $v = $f->{$pri}; $v||=$f->{lc $pri};
			#return {id=>$v,value=>$class->stringify($v)}; #$f->{fkd})};	
			#return $class->retrieve($v);
			return $v;
		}
		else
		{
			goto __JUMP_TO_MULTI if $multi_match;
			
			my $sql = "select $q_primary from $q_table where $concat = ? and $fkclause";
			#print STDERR "\nMark1: sql:\n\t$sql\nval=[".lc($val)."]\n\n" if $debug;
			my $sth = $dbh->prepare($sql);
			$sth->execute(lc($val));
			
			if($sth->rows)
			{
				my $f = $sth->fetchrow_hashref;
				print STDERR "$class->validate_string($val): RETURN at $concat is =$val\n" if $debug;
				my $v = $f->{$pri}; $v||=$f->{lc $pri};
				#return {id=>$v,value=>$class->stringify($v)}; #$f->{fkd})};	
				return $v;
			}
			else
			{
			
				#print STDERR "dbcols: ".Dumper(\@dbcols,\@fmt); 
				my $sql = "select $q_primary from $q_table where lower(".$dbh->quote_identifier($dbcols[0]).")=? and $fkclause";
				my $sth = $dbh->prepare($sql);
				$sth->execute(lc($val));
				
				if($sth->rows)
				{
					print STDERR "$class->validate_string($val): RETURN at \$dbcols[0] ($dbcols[0]) is =$val\n" if $debug;
					my $f = $sth->fetchrow_hashref;
					my $v = $f->{$pri}; $v||=$f->{lc $pri};
					#my $res = {id=>$v,value=>$class->stringify($v)}; #$f->{fkd})};	
					return $v;
					#my $res = {id=>$f->{$pri},value=>$class->stringify($f->{$pri})}; #$f->{fkd})};	
					#open(LOG,">/tmp/fklog.log");
					#print STDERR "Matched val [$val] with sql [$sql], pri=[$pri], f->{pri}=[$f->{$pri}]\n" if $debug;
					#print STDERR "Res: ".Dumper($res,$col) if $debug;
					#print LOG "Matched val [$val] with sql [$sql], pri=[$pri], f->{pri}=[$f->{$pri}]\n";
					#print LOG "Res: ".Dumper($res,$col);
					#close(LOG);
					#return $res;
				}
				else
				{
	__JUMP_TO_MULTI:
					#my $sql = "select $q_primary from $q_table where $concat like ? and $fkclause";
					
					#print STDERR "$0: sql: $sql\n" if $debug;
					
					#my $sth = $dbh->prepare($sql);
					
					
					$val =~ s/(^\s+|\s+$)//g;
					
					#my $x = $sep;
					#$x=~s/\./\\./g;
					
					my $orig_val = $val;
					
					if(!defined $val || $val eq '')
					{
						#print STDERR "$class->validate_string($val): RETURN at [NULL] for val [mark2]\n" if $debug;
						#return {id=>0,value=>''};
						$@ = undef;
						return ();
					}
					else #if($val =~ /$sep/)
					{
						#print STDERR "$class->validate_string($val): RETURN at VAL NOT NULL for val [mark3] - TBD write partial matching\n" if $debug;
						#return {id=>0,value=>''};
	#=head1
						#print STDERR "$class: Couldn't match with first LIKE, trying something else...\n";
						#print Dumper $gentab, $group;
						
						
						my ($fklookup_sql,@args) = $class->get_fkquery_sql($val,$fkclause,$debug);
						
						$fklookup_sql = "select $q_primary from ".$fklookup_sql;
						
						$sth = $dbh->prepare($fklookup_sql);
						$sth->execute(@args);
							
						
							
						if($sth->rows > 1) # && $val ne $sep)
						{
							#$multi_match = 1;
							if($multi_match)
							{
								my @list;
								while(my $res = $sth->fetchrow_hashref)
								{
									#3print STDERR "$class: Multi-match for $val: `$pri`='$res->{$pri}'\n";
									push @list, $res->{$pri} || $res->{lc $pri};
								}
								#return {id=>join(',',@list)}; #,list=>\@list};
								return wantarray ? @list : \@list;
							}
							else
							{
								
								print STDERR "$class->validate_string($val): RETURN at ambiguous [ERROR] for $concat like $val\n" if $debug;
								#return {error=>"\"$orig_val\" matches more than one ".$class->meta->{class_noun}};
								$@ = "\"$orig_val\" matches more than one ".$class->meta->{class_noun};
								return ();
							}
						}
						else
						{
							my $f = $sth->fetchrow_hashref;
							if($f)
							{
								print STDERR "$class->validate_string($val): RETURN at 2[$fklookup_sql] match [".join('|',@args)."]\n" if $debug;
								#return {id=>$f->{$pri},value=>$class->stringify($f->{$pri})}; #$f->{fkd})};
								my $v = $f->{$pri}; $v||=$f->{lc $pri};
								#return {id=>$v,value=>$class->stringify($v)}; #$f->{fkd})};	
								return $v;
							}
							else
							{
								#if(!$adder)
								#{
								#	return $col->validate_string($sep.$val,$check_pri,$multi_match,1,$debug)
								#}
								#else
								#{
									print STDERR "$class->validate_string($val): RETURN at no match [ERROR] for [$fklookup_sql] match [".join('|',@args)."]\n" if $debug;
									#return {error=>"No ".$class->meta->{class_noun}."(s) match \"$orig_val\""};
									$@ = "No ".$class->meta->{class_noun}."(s) match \"$orig_val\"";
									$! = "NO_MATCH";
									return ();
								#}
							}
						}
	#=cut					
					}
				}
			}
		}
		
		print STDERR "$class->validate_string($val): RETURN at END UNKNOWN [ERROR]\n" if $debug;
		#return {error=>"Unknown Error"};
		$@ = "Unknown Error";
		return ();
		
	
	}
	
	# Function: check_acl($acl)
	#	Checks to see if a user is logged in, and if one is logged in, it checks the given ACL, otherwise returns false if the 
	#	user is not logged in . However, if no ACL is given ($acl is under), then it returns true.
	#
	# Parameters:
	#	$acl - the ACL arrayref to check, e.x.: ['Role.QualityMgr','Dept.IT','jbryan']
	#
	# Returns:
	#	- false (under or 0) if no user or check_acl fails for that user
	#	- 1 if no user logged in but $acl is not under
	#	- The name of the ACL group or entity that check_acl passed on if check_acl() is 'good'
	sub check_acl #($acl)
	{
		my $self = shift;
		my $acl = shift;
		
		# Defaults to TRUE if NO ACL
		# Defaults to FALSE if HAS ACL but NO USER
		# Otherwise, it checks $acl against $self->user
		my $user = AppCore::Common->context->user;
		print STDERR "$self: user: $user\n";
		return 'EVERYONE' if $acl && !$user && $acl->[0] eq 'EVERYONE';
		
		return $acl ? ( $user ? $user->check_acl($acl) : 0 ) : 1;
	}
	
	sub schema_columns
	{
		my $class = shift;
		my $meta = $class->meta;
	
		my @list;
		foreach my $field (@{$meta->{schema}})
		{
			next if ! AppCore::DBI->check_acl($field->{read_acl});
			
			push @list, $field->{field};
		}
		
		return @list;
	}
	
	
	# Variable: %DB_CACHE
	# Holds cached db handles as "host.db.user.pass" keys 
	my %DB_CACHE;
	
	# Function: dbh
	# Returns a DBI database handle object.
	# 
	# Parameters: 
	#	- $db	- The database name
	#	- $host	- The hostname or IP address of the database server
	#	- $user	- user name
	#	- $pass	- password
	#
	# Default Strategy:
	# If any of the parameters are undef (which is the default value), dbh() will check <%DBPARAMS_CLASS_CACHE> 
	# using the class name called with as the key, expecting to get a hashref in which it checks for the missing parameter.
	# If the parameter is not specified in <%DBPARAMS_CLASS_CACHE>, then it defaults to 'DEFAULT_' + param name, e.g.
	# default for $db is the constant <DEFAULT_DB>.
	#
	
	sub dbh#($db=undef,$host=undef,$user=undef,$pass=undef)
	{ 
		my $class = shift;
		$class = ref $class if ref $class;
		
		my $db   = shift || $DBPARAMS_CLASS_CACHE{$class}->{DEFAULT_DB}   || DEFAULT_DB;
		my $host = shift || $DBPARAMS_CLASS_CACHE{$class}->{DEFAULT_HOST} || DEFAULT_HOST;
		my $user = shift || $DBPARAMS_CLASS_CACHE{$class}->{DEFAULT_USER} || DEFAULT_USER;
		my $pass = shift || $DBPARAMS_CLASS_CACHE{$class}->{DEFAULT_PASS} || DEFAULT_PASS;
		
		my %attrs = @_ ? @_ : %DBI_ATTRS;
		
		use Data::Dumper;
		my $key = join ':', $host, $db, $user, $pass;
		#print STDERR "$class->dbh($db): $key - Mark 1\n"; #: ".Dumper(\%attrs);
		return $DB_CACHE{$key} if $DB_CACHE{$key};
		
		#print STDERR "dbh($db): CACHE MISS: $key\n"; # ********************************** Mark 2: ".Dumper(\%attrs);
		
		eval {
		
		#print STDERR "Connecting to db $db, host $host...\n";
		$DB_CACHE{$key} = 
	#$host eq '10.0.1.5' ? 
	#		DBI::ReplicationProxy->connect($db) : 
			DBI->connect("DBI:mysql:database=$db;host=$host;mysql_enable_utf8=0",$user, $pass,{'RaiseError' => 1, %attrs});
		#print STDERR "Connected.\n";
		
		};
		if($@)
		{
			#print "\n\n" .date(). ": Error stacktrace:";
			#print_stack_trace;
			#print "\n\n";
			die $@;
		}
		
		return $DB_CACHE{$key};
	}
	# 
	
	sub insert
	{
		my $self = shift;
		my $dbh = $self->db_Main;
	# 	if($dbh->isa('DBI::ReplicationProxy'))
	# 	{
	# 		# disconnect from the slave, forcing all queries to the master for the life of this new object
	# 		#undef $dbh->{slave};
	# 		$dbh->single_master_mode(1);
	# 		#print "Un-def'd the slave\n";
	# 	}
	# 	else
	# 	{
	# 		#print "Not a rep proxy (".ref($dbh).")/(".ref($self).")/($self)\n";
	# 	}
		return $self->SUPER::insert(@_);
		
	}
	*create = \&insert;
	
	# Patch Class::DBI's impl of _insert_row to use the sth attribute 'mysql_insertid' instead of the $dbh attribute
	sub _insert_row {
		my $self = shift;
		my $data = shift;
		eval {
			my @columns = keys %$data;
			my $sth     = $self->sql_MakeNewObj(
				join(', ', @columns),
				join(', ', map $self->_column_placeholder($_), @columns),
			);
			$self->_bind_param($sth, \@columns);
			$sth->execute(values %$data);
			my @primary_columns = $self->primary_columns;
			$data->{ $primary_columns[0] } = $sth->{mysql_insertid} || $self->_auto_increment_value
				if @primary_columns == 1
				&& !defined $data->{ $primary_columns[0] };
		};
		if ($@) {
			my $class = ref $self;
			return $self->_db_error(
				msg    => "Can't insert new $class: $@",
				err    => $@,
				method => 'insert'
			);
		}
		return 1;
	}
	
	sub set_if
	{
		my $self = shift;
		my $hash = shift;
		if(!ref $hash && @_)
		{
			$hash = { $hash => shift };
		}
		
		if(!ref $hash)
		{
			$@ = "HASH ref required";
			return undef;
		}
		
		my $changed = 0;
		foreach my $key (keys %$hash)
		{
			if($self->get($key) ne $hash->{$key})
			{
				$self->set($key,$hash->{$key});
				$changed ++;
			}
		}
		
		return $changed;
	}
	
	# 
	# 
	# sub retrieve {
	#     my($proto, $id) = @_;
	#     my($class) = ref $proto || $proto;
	# 
	#     my $dbh = $class->db_Main;
	#     
	#     
	#     # Class::DBI does SELECT after INSERT
	#     # Since the replication might not hit the slave RIGHT away, force
	#     # the retrieve to use the MASTER for the select instead of the slave
	#     unless( caller->isa('Class::DBI') && $dbh->isa('DBI::ReplicationProxy') ) {
	# 	return $class->SUPER::retrieve($id);
	#     }
	# 
	#     print STDERR "HIT: retrieve $class / $proto / $id\n";
	#     my($id_col) = $class->columns('Primary');
	# 
	#     my $data;
	#     eval {
	#         my $sth = $dbh->master->prepare_cached('SELECT ' . join(', ', $class->columns('Essential')),
	# 	    'FROM '. $class->table,
	# 	    'WHERE '. $class->columns('Primary') . ' = ?',
	# 	undef,1);
	#         $sth->execute($id);
	#         $data = $sth->fetchrow_hashref;
	#         $sth->finish;
	#     };
	#     if ($@) {
	#     	warn "Error: $@";
	#         $class->DBIwarn($id, 'GetMe');
	#         return;
	#     }
	# 
	#     return unless defined $data;
	#     return $class->construct($data);
	# }
	
	
	
	# Function: onfork
	# Can be called to clear DB handles when forking the process
	sub clear_handle_cache
	{
		%DB_CACHE = ();
	}
	
	
	##############################################################################
	# Group: Transactional Support
	# from http://wiki.class-dbi.com/wiki/Using_transactions
	# For use with CDBI
	sub do_transaction 
	{	
		my($class,$code,@args) = @_;
		
		$class->_invalid_object_method('do_transaction()') if ref($class);
		
		my @return_values = ();
		my $dbh = $class->db_Main;
		
		# Localize AutoCommit database handle attribute
		# and turn off for this block.
		local $dbh->{AutoCommit};  # Note: Leaks memory with Perl 5.6.1. Upgrade!
		
		eval 
		{
			@return_values = $code->(@args);
			$class->dbi_commit;
		};
		if ($@) 
		{
			my $error = $@;
			eval { $class->dbi_rollback; };
			if ($@) 
			{
				my $rollback_error = $@;
				$class->_croak("Transaction aborted: $error; "
						. "Rollback failed: $rollback_error\n");
			}
			else 
			{
				$class->_croak("Transaction aborted (rollback "
						. "successful): $error\n");
			}
			$class->clear_object_index;
			return;
		}
		return(@return_values);
	
	} #eosub--do_transaction
	
	# Function: get_columns_list
	# Returns a list of columns for a table
	sub get_columns_list
	{
		my $this = shift;
	
		my $dbh = $this->db_Main();
	
		my $table = shift || $this->table;
			
		$table = $this if !$table;
	
		my $sth = $dbh->prepare("show fields from `$table`");
		$sth->execute();
			
		my @fields;
		while (my $ref = $sth->fetchrow_hashref()) 
		{
			#print Dumper $ref;
			push @fields, $ref->{field} || $ref->{Field};
		}
		
		#print "== Fields for [$table]: ".join(', ',@fields)."\n";
		return @fields;
	}
	
	# Function: default_setup
	# This is for CDBI child classes to atuomatically load the list of columns for the table
	sub default_setup
	{
		my $self = shift;
		my $table = shift;
		
		#print "$self: default_setup($table)\n";
		
		$self->table($table);
		$self->columns(All => $self->get_columns_list($table));
	
	}
	
	## Generic use - not CDBI specific
	sub fields_list
	{
		my $this = shift;
		my $dbh = shift;
		my $table = shift;
		
		$table = $this if $table eq undef;
		
		$table =~ s/;/_/; # very basic protection
		
		#AppCore::debug("show fields from $table;\n");
		my $sth = $dbh->prepare("show fields from $table;");
		$sth->execute();
		
		my @fields;
		while (my $ref = $sth->fetchrow_hashref()) 
		{
			push @fields, $ref; #->{field} || $ref->{Field};
		}
		return \@fields;
	}
	
	
	
	
	sub save_hash
	{
		my $class = shift; #(ref($_[0]) ne undef || $_[0] eq __PACKAGE__)?shift:undef;
		my ($dbh,$table,$hash,$field_id,$flag_forcenew) = @_;
		
		#AppCore::debug("table:$table,hash:$hash,field_id:$field_id\n");
		
		$field_id = lc($table).'id' if !$field_id;# eq undef;
	
		my $fields = $class->fields($dbh,$table);
		#die "hi";
		
		if(!exists $hash->{$field_id} || !defined $hash->{$field_id} || $hash->{$field_id} eq '' || $flag_forcenew)
		{
			#die "mark1";
			my $f = '';
			my $v = '';
			
			$fields->{lc $_} = $fields->{$_} foreach keys %$fields;
			
			my @values;
			foreach(keys %$hash)
			{
				#print STDERR "key=$_, value=[$hash->{$_}]\n";
				if(exists $fields->{$_} && $_ ne $field_id)
				{
					$f .= "`$_`,";
					$v .= '?,';
					push @values,$hash->{$_}; #AppCore::DB->sqlquote($phone_dat->{$_}).',';
				}
			}
			
			chop($f);
			chop($v);
			
			print STDERR ("sql=insert into $table ($f)\n values ($v);\n,values=",join('|',@values),"\n");
			eval
			{
				$dbh->do("insert into $table ($f) values ($v);",undef,@values);
			};
			if($@)
			{
				print STDERR "ERROR: $@\n";
				print STDERR "sql=insert into $table ($f)\n values ($v);\n,values=",join('|',@values),"\n";
				print_stack_trace();
				die $@;
			};
			
			my $sth = $dbh->prepare("SELECT max($field_id) as `id` FROM $table");
			$sth->execute();
			
			my $id = $sth->fetchrow_hashref()->{id};
			#print STDERR "******************* ID=[$id]\n";
			#$hash->{$field_id} = $dbh->last_insert_id(undef,undef,undef,undef); #
			$hash->{$field_id} = $id;
			#print Dumper $hash;
			#print STDERR ("Saved NEW (insert): $table.$field_id: [$hash->{$field_id}]\n");
		}
		else
		{
			#die "mark2 [".$hash->{$field_id}."]";
			my $sql = "update $table set ";
			
			$fields->{lc $_} = $fields->{$_} foreach keys %$fields;
			
			my @values;
			foreach(keys %$hash)
			{
				#print "$_ = $phone_dat->{$_}\n";
				#$sql .= "$_ = ".AppCore::DB->sqlquote($phone_dat->{$_}).', ' if exists $fields->{$_} && $_ ne 'id';
				if (exists $fields->{$_} && $_ ne $field_id)
				{
					$sql .= "`$_`=?, ";
					push(@values,$hash->{$_});
				}
			}
			
			$sql = substr($sql,0,-2);
			$sql .= " where $table.$field_id=?";
			push(@values,$hash->{$field_id});
		
			#print STDERR "** SAVING [UPDATE]: $sql, values=".join('|',@values)."\n";
			$dbh->do($sql,undef,@values);
			
			#debug("Saved OLD (update): $table.$field_id = [$hash->{$field_id}]\n");
		}
		
		#$dbh->do('flush tables');
		
		return $hash;
	}
	
	
	
	sub get_class_defaults { shift->get_table_defaults(shift->table) }
	
	my %cache_table_defaults;
	sub get_table_defaults
	{
		shift; # $self
		my $table = shift;
		return $cache_table_defaults{$table}->{hash} if defined $cache_table_defaults{$table}->{hash} && 
			!AppCore::DBI->has_updated_since($cache_table_defaults{$table}->{stamp},$table);
		my $dbh = shift || AppCore::DBI->dbh_auto($table);
		die "Cannot find db handle for table '$table': None provided or dbh_auto couldn't resolve." if !$dbh;
		my $sth = $dbh->prepare_cached('explain '.lc($table),undef,1);
		$sth->execute;
		my %defs;        
		while(my $ref = $sth->fetchrow_hashref)
		{
			#print Dumper $ref;
			my $f = $ref->{field};
			$f = $ref->{Field} if !defined $f;
			my $k = $ref->{default};
			$k = $ref->{Default} if !defined $k;
			#print "$f = [".(defined $k?$k:'<undef>')."]\n";
			$defs{$f} = $k;
		}
		$sth->finish;
		
		#print Dumper \%defs;
		
		foreach my $key (keys %defs)
		{
			$defs{$key} = date() if $defs{$key} eq 'CURRENT_TIMESTAMP';
		}
		
		$cache_table_defaults{$table} = {hash=>\%defs,stamp=>date()};
		
		
		return \%defs;
	}
	
	my %cache_table_unique;
	sub get_table_unique
	{
		#shift; # $self
		my $table = shift;
		#print STDERR "get_table_unique: [$table]\n";
		return $cache_table_unique{$table}->{res} if defined $cache_table_unique{$table}->{res} && 
			!AppCore::DBI->has_updated_since($cache_table_unique{$table}->{stamp},$table);
		my $dbh = shift || AppCore::DBI->dbh_auto($table);
		my $sth = $dbh->prepare_cached('explain '.lc($table),undef,1);
		$sth->execute;
		my %res;
		while(my $ref = $sth->fetchrow_hashref)
		{
			#print Dumper $ref;
			my $f = $ref->{field};
			$f = $ref->{Field} if !defined $f;
			my $k = $ref->{key};
			$k = $ref->{Key} if !defined $k;
			#print "$f = [".(defined $k?$k:'<undef>')."]\n";
			$res{$f}=1 if $k eq 'UNI' || $k eq 'PRI';
		}
		$sth->finish;
		
		#print Dumper \%defs;
		
		$cache_table_unique{$table} = {res=>\%res,stamp=>date()};
		
		
		return \%res;
	}
	
	sub get_class_primary { shift->primary_column } #get_table_primary(shift->table) }
	
	my %cache_table_primary;
	sub get_table_primary
	{
		shift; # $self
		my $table = shift;
		return $cache_table_primary{$table} if defined $cache_table_primary{$table};
		my $dbh = shift || AppCore::DBI->dbh_auto($table);
		my $sth = $dbh->prepare_cached('explain '.lc($table),undef,1);
		$sth->execute;
		my $pri;
		while(my $ref = $sth->fetchrow_hashref)
		{
			if(lc($ref->{key}||$ref->{Key}||'') eq 'pri')
			{
				$pri = $ref->{field}||$ref->{Field};
				last;
			}
		}
		
		$cache_table_primary{$table} = $pri;
		
		return $pri;
	}
	
	sub last_update_time
	{
		shift;
		#my $stamp = shift;
		my $table = shift;
		
		my $dbh = AppCore::DBI->dbh_auto($table);
		my $sth = $dbh->prepare_cached('show table status like ?',undef,1);
		$sth->execute($table);
		my $ref = $sth->rows ? $sth->fetchrow_hashref : undef;
		return $ref->{Update_time} || $ref->{update_time};
	}
	
	sub has_updated_since
	{
		shift;
		my $stamp = shift||'';
		my @tables = shift;
		
		foreach my $table (@tables)
		{
			my $dbh = AppCore::DBI->dbh_auto($table);
			my $sth = $dbh->prepare_cached('show table status like ?',undef,1);
			$sth->execute($table);
			my $ref = $sth->rows ? $sth->fetchrow_hashref : undef;
			$sth->finish;
			my $time = $ref->{Update_time} || $ref->{update_time};
			#die "Cannot find last update time for $table" if !$sth->rows || !defined $time;
			my $ret = 0;
			
			if(!$sth->rows || !defined $time)
			{
				$ret = 1;
			}
			else
			{
				#print "$table: Update_time=$time, stamp=$stamp\n";
				$ret = 1 if ($time cmp $stamp) > 0;
				if($ret)
				{
					#print "$table: Update_time=$time, stamp=$stamp, ret=$ret\n";
				}
			}
			
			
			return $ret;
		}
		
		return 0;
	}
	
	
	
	sub load_hash
	{
		my $class = shift; #(ref($_[0]) ne undef || $_[0] eq __PACKAGE__)?shift:undef;
		my ($dbh,$table,$id,$field_id) = @_;
		
		$field_id = 'id' if !$field_id;
		
		my $sql = (lc($id) =~ /^select/)?$id:"SELECT * FROM $table where $field_id = ?";
		
		#AppCore::debug("sql=$sql\n");
		#print STDERR "sql=$sql\n";
		
		my $sth = $dbh->prepare($sql);
		$sth->execute(($sql=~/\?/)?($id):());
		
		return undef if !$sth->rows;
		
		my $ref = $sth->fetchrow_hashref();
		
		$sth->finish();
		
		return $ref;
	}
	
	sub get_where_clause
	{
		my $class = shift;
		my %inq = %{shift()||{}};
		#my %types = %{shift()||{}};
		#my $gentab = shift;
			
		#AppCore::Common::print_stack_trace();
		#print STDERR "Debug: get_where_clause() for $class: inq=".Dumper(\%inq)."\n";
		
		my @clause;
		my @args;
		
		my %types = %{ $class->meta->{field_map} || {} };
		
		my $dbh = $class->db_Main;
		my $dsn = $dbh->{Name};
		$dsn =~ /database=([^;]+)/;
		my $db = $dbh->quote_identifier($1);
		
		my $table = $dbh->quote_identifier($class->table);
		
		#push @clause, $_.' like ?' foreach @key_list;
		
		#print STDERR "Debug: compose_where_clause(): types=".Dumper(\%types)."\n";
		
		foreach my $dbcol (keys %types)
		{
			my $type = $types{lc $dbcol}->{type} ||'';
			if($type =~ /Date/ && !defined $inq{$dbcol})
			{
				my $a = $inq{$dbcol.'_start_date'};
				my $b = $inq{$dbcol.'_end_date'};
				undef $a if $a && $a eq '0000-00-00';
				undef $b if $b && $b eq '9999-99-99';
				#print STDERR "$dbcol: \$a=$a,\$b=$b\n";
				if($a && $b)
				{
					push @clause, "($db.$table.`$dbcol` >= ? and `$dbcol` <= ?)";
					push @args, ($a,$b);
				}
				elsif($a && !$b)
				{
					push @clause, "$db.$table.`$dbcol` >= ?";
					push @args, $a;
				}
				elsif(!$a && $b)
				{
					push @clause, "$db.$table.`$dbcol` <= ?";
					push @args, $b;
				}
				#push @clause, 
			}
			else
			{
				#my $v = $inq{$dbcol};
				
				if(!defined $inq{$dbcol} || $inq{$dbcol} eq '' || $inq{$dbcol} eq '*') # || !$inq{$dbcol})
				{
					delete $inq{$dbcol};
				}
				else
				{
					if(ref $inq{$dbcol} eq 'ARRAY')
					{
						my @values = @{ $inq{$dbcol} || [] };
						my $q = join ',', ( ('?') x ($#values+1) );
						push @clause, "$db.$table.`$dbcol` in ($q)";
						push @args, @values;
					}
					else
					{
						$inq{$dbcol} =~ s/\*/\%/g;
						
						
						#print STDERR called_from().": col=$dbcol,type=$type\n";
						if($type eq 'PrimaryForeignKey' && $inq{$dbcol} =~ /^[\d\,]+$/)
						{
							push @clause, "$db.$table.`$dbcol` in (".$inq{$dbcol}.")";
						}
						else
						{
							if(lc($type) =~ /number/ && $inq{$dbcol}!~/^[+-]?\d+(?:\.\d?)?$/)
							{
								push @clause, '0';
							}
							else
							{
								my $string = $type =~ /(varchar|text|enum)/i ?1:0;
								#print STDERR "\$type=[$type], \$string=[$string]\n";
								$inq{$dbcol} = $string ? "\%$inq{$dbcol}\%" :  $inq{$dbcol};
								
								push @clause, "$db.$table.`$dbcol` ". ($string?' like ' : '=').' ? ';
								push @args, $inq{$dbcol};
							}
							
						}
					}
				}
				
				#if(defined $v)
				#{
				#	push @clause, "`$dbcol` like ?";
				#	push @args, $v;
				#}
			}
		}
		
		#push @args, $inq{$_} foreach @key_list;
		#print "\@clause: ".Dumper \@clause;
		
		my $cl = join ' and ',@clause;
		
		#die Dumper \%inq, \@clause, \@args, \@key_list, $cl;
		
		
		$cl = '1' if !defined $cl || $cl eq '';
		#my $col0 = $columns[0]->dbcolumn;
		
		#my ($tables,$cl2,@args2) = AppCore::DBI->apply_user_filters($gentab);
		#$cl .= " and $cl2";
		#push @args, @args2;
		
		#print STDERR Dumper ''.$class,\%inq,\%types,"cl=",$cl,\@args;
		#print STDERR "cl=$cl\n";
		
		return (undef,$cl,@args);
	
	}
	
	sub auto_schema
	{
		my $class = shift;
		my @list;
		my $sth = $class->db_Main->prepare_cached('explain `'.$class->table.'`',undef,1);
		$sth->execute;
		while(my $ref = $sth->fetchrow_hashref)
		{
			$ref->{lc $_} = $ref->{$_} foreach keys %$ref;
			push @list, $ref;
			#print Dumper $ref;
			#$f = $ref->{Field} if !defined $f;
			#$k = $ref->{Default} if !defined $k;
			#print "$f = [".(defined $k?$k:'<undef>')."]\n";
		}
		$sth->finish;
		return @list;
	}
	
	sub by_field
	{
		#my ($class,$field,$val) = @_;
		#my @list = $class->search($field=>$val);
		my $class = shift;
		my @list = $class->search(@_);
		return @list ? shift @list : undef;
	}
	
	sub before_update_diff
	{
		my $self = shift;
		
		## Grab the current values from the database
		my $dbh = $self->db_Main;
		my @cols = map {$dbh->quote_identifier($_->{field})} @{$self->meta->{schema}};
		my $sth = $dbh->prepare('select '.join(',',@cols).' from '.$dbh->quote_identifier($self->table).' where '.$dbh->quote_identifier($self->primary_column).'=?');
		#my $sth = $self->db_Main->prepare('select * from '.$self->table.' where '.$self->primary_column.'=?');
		$sth->execute($self->id);
		my $orig_values = $sth->fetchrow_hashref;
		
		## Compare current values with the new values stored in $self
		my %changes;
		my $has_field_changes = 0;
		
		foreach my $key (keys %$orig_values)
		{
			my $new_val = eval '$self->get($key)';
			
			if($new_val .'' ne $orig_values->{$key} .'')
			{
				$changes{$key} = $new_val;
			}
			
			
			#push @missing, $so->field_meta($key) || {title=>AppCore::Common::guess_title($key)} if !$so->get($key);
			
			$has_field_changes = 1;
		}
		
		return wantarray ? %changes : (\%changes, $has_field_changes);
	}
	
# 	# Default implementation of apply_mysql_schema() - feel free to override in subclasses
# 	sub apply_mysql_schema
# 	{
# 		my $self = shift;
# 		$self->mysql_schema_update(ref($self));
# 	}
	
	sub auto_new_dbh
	{
		my $self = shift;
		my $db = shift;
		my $opts = shift || {};
		my $dbh = undef;
		eval { $dbh = AppCore::DBI->dbh($db,$opts->{host},$opts->{user},$opts->{pass}) };
		
		if($@ =~ /Unknown database '$db'/)
		{
			# Assume that default user can create databases
			AppCore::DBI->dbh('mysql')->do('CREATE DATABASE `'.$db.'`');
			#push @sql, 'CREATE DATABASE `'.$db.'`'."\n";
			$dbh = AppCore::DBI->dbh($db,$opts->{host},$opts->{user},$opts->{pass});
		}
		else
		{
			die $@ if $@;
		}
		
		return $dbh;
	}
	
	
	
	# Function: mysql_schema_update($db,$table,$fields,$opts)
	# Static function.
	#
	# Example Usage:
	#     perl -MAppCore::Common -e "mysql_extract_current_schema('bryanuno','games',{dump=>1})" > out.txt
	#
	# Parameters:
	# $db - Database name in which to find the table
	# $table - Name of the table to either CREATE or ALTER
	# $fields - A arrayref, each row is a hashref 
	#           having the following keys: Field, Type, Null,Key,Default,Extra (see 'explain TABLE' in mysql)
	# $opts - A hashref of options. Key/Values recognized:
	#   'host' - MySQL host to use (can be undef - will use default host in AppCore::DBI)
	#   'user' - User to use when connecting - if none specified, will use default user in AppCore::DBI
	#   'pass' - Password to use when connecting - if none specified, will use default pass in AppCore::DBI
	#   'after_create' - EITHER an Anon sub (see below - dbh is first arg) OR an array ref of rows to insert
	#                    Called AFTER create table is run
	#   'after_alter' - Anon sub, called BEFORE the ALTER statements run.
	#                    Sub will be given the $dbh as its first arg (dbh logged in)
	#   'before_alter' - Anon sub, called AFTER the ALTER statemets run.
	#                    Sub will be given the $dbh as its first arg (dbh logged in)
	
	our @mysql_schema_sql_debug_output;
	
	sub mysql_schema_update#($db,$table,$fields,$opts)
	{
		#eval 'use AppCore::Auth::Util' ;
		if(!@_)
		{
			die 'Usage: mysql_schema_update($db,$table,$fields,$opts) or mysql_schema_update($pkg,$class,...)'; 
		}
		
		# Allow AppCore::DBI-derived classes to call mysql_schema_update() as a class method, e.g.
		# MySubClass->mysql_schema_update() - and have it Do The Right Thing.
		if(@_ == 1 && $_[0])
		{
			return $_[0]->mysql_schema_update($_[0]);
		}
		
# 		AppCore::Auth::Util->authenticate;
# 		my $user = AppCore::Common->context->user;
# 		my $is_admin = $user ? $user->check_acl(['ADMIN']) : undef;
# 		die "Must be logged in as an administrator to run 'mysql_schema_update' commands ($user,$is_admin)" if $^O !~ /Win32/ && (!$user || !$is_admin);
		
		if(ref $_[2] ne 'ARRAY' && @_ >= 1)
		{
			# Assume the args are in the form of a Package, and optional list of classes to load the schema from.
			# E.g. if called with ('LaunchPad::Project','LaunchPad::ActionPlan') as args,
			# assume that the first arg is the name of the package to load, and assume that the second arg
			# is the name of a class that has $class->meta->{schema} in the format expected for the $fields
			# argument, below. If only one arg, assume its the package to load AND it has the meta->{schema} to apply.
			
			my $pkg;
			my @classes;
			
			if(@_ == 1)
			{
				$pkg = shift;
				@classes = ($pkg);
			}
			else
			{
				$pkg = shift;
				@classes = @_;
			}
			
			eval 'use '.$pkg;
			die "Error loading package '$pkg': $@" if $@ && $@ !~ /Can't locate/;
			
			foreach my $class (@classes)
			{
				next if !$class;
					
				print STDERR "Debug: Updating class '$class'\n";
				my $meta = eval '$class->meta';
				if(!$meta || $@)
				{
					$@ = "No meta data returned by meta()" if !$@;
					die "Error getting meta() from '$class': $@";
				}
				
				if(!$meta->{schema} || ref $meta->{schema} ne 'ARRAY')
				{
					die "Error in meta data from '$class': No 'schema' element or invalid 'schema' reference type";
				}
				
				$meta->{db} ||= $meta->{database};
				if(!$meta->{db})
				{
					die "Error in meta data from '$class': No 'db' element";
				}
				
				if(!$meta->{table})
				{
					warn "Warn: Error in meta data from '$class': No 'table' element - not updating";
					return undef;
				}
				
				mysql_schema_update($meta->{db},$meta->{table},$meta->{schema},$meta->{schema_update_opts});
			}
			
			return 1;
			
		
		}
		
		my ($db,$table,$fields,$opts) = @_;
		local $_;
# 		
# 		if($table eq 'pingmap_log')
# 		{
# 			print STDERR "ADMIN OVERRIDE: Not syncing schema for pingmap_log due to large table size\n";
# 			return;
# 		}
		
		my @sql;
		
		my $dbh = __PACKAGE__->auto_new_dbh($opts);
		
		my $q_explain = $dbh->prepare('explain `'.$table.'`');
		my $old_fatal = $SIG{__DIE__};
		$SIG{__DIE__} = sub{return};
		eval '$q_explain->execute()';
		$SIG{__DIE__} = $old_fatal;
		#die $@ if $@ && $@ !~ /Table.*?doesn't exist/;
		#undef $@;
		#$table); 
		
		#die $q_explain->rows;
		# Assume table exists - compare
		if(!$@ && $q_explain->rows)
		{
			my %explain;
			my ($field,$type,$null,$key,$default,$extra,$x);
			# Perl's \(...) creates a ref for each var
			$q_explain->bind_columns(\($field,$type,$null,$key,$default,$extra));
			$explain{$field} = {field=>$field,type=>$type,null=>$null,key=>$key,default=>$default,extra=>$extra} 
				while $q_explain->fetch;
	
			my %fields = map {$_->{field}=>$_} @$fields;			
			my @alter;
			my @changed_columns;
			foreach my $key (keys %fields)
			{
				# Assume if key does not exist in %explain, it doesnt exist in the table
				if(!exists $explain{$key})
				{
					push @alter, 'ALTER TABLE `'.$table.'` ADD '._mysql_fieldspec($fields{$key});
					push @changed_columns, {col=>$key,type=>'ADD'};
				}
				# If key exists in %explain, do a simple eq diff comparrison
				elsif(exists $explain{$key})
				{
					my $a = $explain{$key};
					my $b = $fields{$key};
					my $cnt = 0;
					foreach my $k (keys %$a)
					{
						if($a->{$k} ne $b->{$k})
						{
							# Normalize some nitch cases that are known to be different ...
							
							# Seems MySQL translates the string \r\n into the actual chr 10 && chr 13
							next if $a->{$k} eq "\r\n" && $b->{$k} eq '\r\n';
							# YES Null from DB and an undef value in $fields is OK
							next if $k eq 'null' && 
								$a->{$k} eq 'YES' && (!defined $b->{$k} || $b->{$k} eq '1');
							# NO Null from DB and a 0 value in $fields is OK
							next if $k eq 'null' && 
								$a->{$k} eq 'NO' && $b->{$k} eq '0';
							# Users of the class sometimes don't uppercase textual "not null" values - so here we do
							next if $k eq 'null' && 
								$a->{$k} eq 'NO' && uc $b->{$k} eq 'NO';
							# Given the type 'integer' (or 'int') to create/alter gives back int(11) in the 'explain ...' stmt
							next if $k eq 'type' && 
								$a->{$k} eq 'int(11)' && ($b->{$k} eq 'integer' || $b->{$k} eq 'int');
							# Translate shorthand for varchar(255) - varchar without modifier is not reconized by mysql,
							# but I allow it here and in the _fieldspec sub and translate it to varchar(255) before mysql sees it
							next if $k eq 'type' && 
								$a->{$k} eq 'varchar(255)' && $b->{$k} eq 'varchar';
							# If type is integer and default is 0 in the db, then here $b->{$k} is '' -- we'll go ahead and allow it
							next if $k eq 'default' &&
								$a->{$k} eq '0' && !$b->{$k} &&
								lc $a->{type} =~ /^int/;
							# Primary Keys that are auto-increment have Null set to NO when seen by 'explain' but the null
							# key is typically undef in the $fields hash - thats okay.
							next if $k eq 'null' && 
								$a->{$k} eq 'NO' && !defined $b->{$k} && 
									$b->{key} eq 'PRI' &&
									$b->{extra} eq 'auto_increment';
							# Even if user specs NULL on a timestamp column, explain returns NOT NULL - ignore and don't try to alter
							next if $k eq 'null' && 
								$a->{$k} ne $b->{$k} &&
								lc $a->{type} eq 'timestamp';
							# timestamp with NULL defaults return CURRENT_TIMESTAMP from mysql - this is valid, just ignore
							# on some systems, it also returns 'on update CURRENT_TIMESTAMP' for key 'extra' - also valid, just ignore
							next if ($k eq 'default' || $k eq 'extra') &&
								uc $a->{$k} =~ 'CURRENT_TIMESTAMP' && !$b->{$k} &&
								lc $a->{type} eq 'timestamp';
								
							# Multiple keys report oddly, so ignore them...
							next if $k eq 'key' && 
								$a->{$k} eq 'MUL' && !$b->{$k};
								
							print STDERR "Debug: k=$k, a=$a->{$k}, b=$b->{$k}, type=$a->{type}\n";
							$cnt ++;
						}
					}
					
					if($cnt > 0)
					{
						push @alter, 'ALTER TABLE `'.$table.'` CHANGE `'.$key.'` ' . _mysql_fieldspec($fields{$key});
						push @changed_columns, {col=>$key,type=>'CHANGE'};
					}
				}
			}
			
			foreach my $key (keys %explain)
			{
				if(!exists $fields{$key})
				{
					# Decide if this is safe
					push @alter, 'ALTER TABLE `'.$table.'` DROP `'.$key.'`';
					push @changed_columns, {col=>$key,type=>'DROP'};
				}
			}
			
			
			if(@alter)
			{
				## Run before_alter sub
				$opts->{before_alter}->($dbh,\@changed_columns) if ref $opts->{before_alter} eq 'CODE';
	
				my $sql = join ";\n", @alter;
				print STDERR "Debug: Alter table: \n$sql\n";
				
				push @sql, $sql;
	
				#my @ok = grep { !/\sDROP\s/ } @alter;
				my @ok = @alter; #grep { !/\sDROP\s/ } @alter;
				foreach my $stmt (@ok)
				{
					eval
					{
						$dbh->do($stmt);
					};
					if($@)
					{
						print STDERR "Error: $@ while executing '$stmt'\n";
						die "$@ while executing '$stmt'";
					}
				}
	
				## Run after_alter sub
				$opts->{after_alter}->($dbh,\@changed_columns) if ref $opts->{after_alter} eq 'CODE';
			}
			
		}
		# Assume table DOES NOT exist - create
		else
		{
			# Compose the SQL statement and send to the server
			my @buff = 'CREATE TABLE `'.$table.'` (';
			push @buff, join (", ", map { _mysql_fieldspec($_) } @$fields);
			push @buff, ')';
			my $sql = join '',@buff;
			
			print STDERR "Debug: $sql\n";
			my $sth = $dbh->prepare($sql);
			
			push @sql, $sql;
			
			$sth->execute;
			
			# Run the post-create code or insertion array
			my $after_create = $opts->{after_create};
			if(ref $after_create eq 'CODE')
			{
				$after_create->($dbh);
			}
			elsif(ref $after_create eq 'ARRAY')
			{
				# If given an array ref, the rows are also expected to be array refs
				# NOTE: The rows must have exactly the number of columns that are in the DB
				# - and in the same order as the $fields hash
				my $cols = scalar @$fields;
				my @buff = ('?') x $cols;
				my $sql = 'INSERT INTO `'.$table.'` VALUES ('.join(',',@buff).')';
				print STDERR "Debug: insert sql: $sql\n";
				my $sth = $dbh->prepare($sql);
				$sth->execute(@$_) foreach @$after_create;
				$sth->finish;
			}		
		}	
		
		push @mysql_schema_sql_debug_output, @sql ? ("<h3>Table: $table</h3>", @sql) : ();
	}
	
	# Function: _mysql_fieldspec
	# PRIVATE
	# Translates an 'explain TABLE' output row into a SQL statement fragment that can be used to create or alter that field
	sub _mysql_fieldspec
	{
		local $_ = shift;
		$_->{null} = uc $_->{null} if defined $_->{null};
		$_->{type} = 'varchar(255)' if lc $_->{type} eq 'varchar';
		"`$_->{field}` $_->{type}".
			($_->{null} eq 'NO' || $_->{null} eq '0' ? ' NOT NULL' : '').
			($_->{key}  eq 'PRI' ? ' PRIMARY KEY' .
				($_->{extra} ? ' '.$_->{extra} : '') : 
			$_->{key}  eq 'UNI' ? ' UNIQUE' : '' ## TODO: Support other varients of Key if needed
			).
			(defined $_->{default} ? (
				$_->{default} eq 'CURRENT_TIMESTAMP' ? '' : 
				$_->{default} eq '' && $_->{type}=~/^int/ ? ' DEFAULT 0' :
				$_->{default} ne 'NULL' ? ' DEFAULT "'.$_->{default}.'"' : 
				'' ) 
			: '')
			#$_->{Extra};
		
	}
	
	# Function: mysql_extract_current_schema
	# Simple utility function to export the schmea for a table from MySQL.
	# If {dump=>1} is passed in the $opts ref, it will print to STDOUT code as a perl call to mysql_schema_update($db,$table,$fields)
	# Example usage:  perl -MAppCore::DBI -e "mysql_extract_current_schema('pci','widget_notes_data',{dump=>1})" > out.txt
	# Or, for a bulk dump of a list of tables and generate packages, dumping each table to its own file:
	#  for i in `echo comments posts post_likes comment_likes read_flags read_post_flags read_comment_flags post_tags`; do(echo Dumping $i ...; perl -Mlib='lib' -MAppCore::DBI -e "AppCore::DBI::mysql_extract_current_schema('jblog','$i',{dump=>1,host=>'database',user=>'root',pass=>'...',pkg=>'BryanBlogs::$i'})"  > "dump_$i.txt"); done;
	sub mysql_extract_current_schema
	{
		my $db = shift;
		my $table = shift;
	
		my $opts = shift || {};
		my $dbh = AppCore::DBI->dbh($db,$opts->{host},$opts->{user},$opts->{pass});
		
		# Sampe basic code as in mysql_schema_update, above, used to explain the database
		my $q_explain = $dbh->prepare('explain `'.$table.'`');
		$q_explain->execute();
		
		my @list;
		my ($field,$type,$null,$key,$default,$extra,$x);
		$q_explain->bind_columns(\($field,$type,$null,$key,$default,$extra));
		push @list, {field=>$field,type=>$type,null=>$null,key=>$key,default=>$default,extra=>$extra} 
			while $q_explain->fetch;
	
		# If {dump} is true, then print to STDOUT a call to mysql_schema_update with some basic variables filled in - ($db,$table,$fields)
		if($opts->{dump})
		{
# 			my $v = Dumper \@list;
# 			$v =~ s/\$VAR1 = //g;
# 			my @l = split/\n/,$v;
# 			s/^\s*/\t\t/g foreach @l;
# 			$l[0]=~s/^\s+/\t/g;
# 			$l[$#l]=~s/^\s+];/\t]/g;
# 			$v = join "\n",@l;

			my $prefix = '';
			if($opts->{pkg})
			{
				$opts->{pkg} =~ s/\s//g;
				my $first = shift @list;
				print qq|
package $opts->{pkg};
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		table		=> '$table',
		
		db		=> '$db',
		db_host		=> '$opts->{host}',
		db_user		=> '$opts->{user}',
		db_pass		=> '$opts->{pass}',
		
		schema	=>
		[
			{
				'field'	=> '$first->{field}',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
|;
				$prefix = "		";
			}
			else
			{

				print "[\n";
			}
			
			foreach my $dat(@list)
			{
				my $q = $dat->{type} =~ /enum/i ? '"' : "'";
				print "$prefix\t{\tfield\t=> '$dat->{field}',\t\ttype\t=> $q$dat->{type}$q";
				
				if(defined $dat->{default} && $dat->{default} ne 'NULL')
				{
					my $q = $dat->{default} =~ /[^\d]/? "'":'';
					print ",\tdefault => $q$dat->{default}$q";
				}
				
				if(defined $dat->{null} && $dat->{null} ne 'YES')
				{
					my $q = $dat->{null} =~ /[^\d]/? "'":'';
					print ",\tnull => $q$dat->{null}$q";
				}
				
				print " },\n";
			}
			
			print "$prefix]\n";
			
			if($opts->{pkg})
			{
				print "	});\n};\n1;\n";
			};
			
			#print "\tmysql_schema_update('$db','$table',\n$v);\n";
		}
		
		return \@list;
	}

	my @CacheClearHooks;
	sub clear_cached_dbobjects
	{
		my $class = shift;
		my $dont_prime = shift || 0;
		
		#print STDERR __PACKAGE__.": Clearing Class::DBI cache...\n";
		$class->clear_object_index;
		foreach my $data (@CacheClearHooks)
		{
			$data->{pkg}->clear_cached_dbobjects;
		}
		
		$class->prime_cached_dbobjects unless $dont_prime;
	}
	
	sub prime_cached_dbobjects
	{
		foreach my $data (@CacheClearHooks)
		{
			my $prime = $data->{prime};
			if($prime)
			{
				#print STDERR "AppCore::DBI->prime_cached_dbojects: Priming cache with ".$data->{pkg}."::${prime}\n"; 
				my $obj = eval { AppCore::Web::Module->bootstrap($data->{pkg}); };
				undef $@;
				if($obj)
				{
					$obj->$prime();
				}
				else
				{
					warn "AppCore::DBI->prime_cached_dbojects: Problem boostraping package '$data->{pkg}' to prime cache, using method on class instead";
					$data->{pkg}->$prime();
				}
			}
		}
	}
	
	sub add_cache_clear_hook
	{
		my $class = shift;
		my $hook_pkg = shift;
		my $prime_cache_method = shift || undef;
		push @CacheClearHooks, { pkg => $hook_pkg, prime => $prime_cache_method };
	}
	
	my $db_modtime_sth; 
	sub setup_modtime_sth
	{
		$db_modtime_sth = AppCore::DBI->dbh('information_schema')->prepare("select sum(UPDATE_TIME) as checksum from TABLES where TABLE_TYPE = 'BASE TABLE' and TABLE_SCHEMA!='mysql'");
	}
	
	setup_modtime_sth();
	
	sub db_modtime
	{
		$db_modtime_sth->execute;
		return $db_modtime_sth->fetchrow_hashref->{checksum};
	}
	
	sub tmpl_select_list
	{
		my $pkg = shift;
		my $cur = shift;
		my $curid = ref $cur ? $cur->id : $cur;
# 		my $include_invalid = shift || 0;
# 		
# 		my @all = $pkg->retrieve_from_sql('1 order by '.$pkg->get_orderby_sql());
# 		my @list;
# 		if($include_invalid)
# 		{
# 			push @list, { 
# 				value 		=> undef,
# 				text		=> '(None)',
# 				selected	=> !$curid,
# 			};
# 		}
# 		foreach my $item (@all)
# 		{
# 			push @list, {
# 				value	=> $item->id,
# 				text	=> $item->display, #$item->last.', '.$item->first,
# 				#hint	=> $item->description,
# 				selected => defined $curid && $item->id == $curid,
# 			}
# 		}
		my $listref = $pkg->stringified_list();
		foreach my $item (@$listref)
		{
			$item->{value} = $item->{id};
			$item->{selected} = defined $curid && $item->{id} == $curid;
		}
		return $listref;
	}

# 	sub search_like
# 	{
# 		my $self = shift;
# 		my %fields = shift;
# 		my @keys = sort keys %fields;
# 		my $ctor = 'search_like_'.join('_', @keys);
# 		if(!$self->can($ctor))
# 		{
# 			$self->add_
# 		}
# 	}
	
};
1;
	
