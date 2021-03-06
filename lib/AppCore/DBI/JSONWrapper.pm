# Package: AppCore::DBI::JSONWrapper
# Designed to emulate a very very simple version of Class::DBI's API.
# Provides get/set/is_changed/update. Not to be created directly, 
# rather you should retrieve an instance of this class
# from another class method.
# Example usage in your class:
# 	sub setup#()
# 		{
# 			my $self = shift;
# 			return $self->{_setup} 
# 				||= AppCore::DBI::JSONWrapper->_init($self, 'setup_data');
# 		}
# Copied from Boards::Post::GenericDataClass.
package AppCore::DBI::JSONWrapper;
{
	use vars qw/$AUTOLOAD/;
	use JSON;
	use Data::Dumper;
	
	
	
	sub _from_json {
		my $json = shift;
		my $obj;
		eval {
			$obj = JSON->new->utf8(1)->decode($json);
		};
		if($@)
		{
			$err = $@;
			AppCore::Common::print_stack_trace();
			warn __PACKAGE__.": Error parsing json: $err, json: $json\n";
		}
		return $obj || {};
	}
	
	sub _to_json {
		my $obj = shift;
		
		my $json; 

		eval {
			$json = JSON->new->latin1(1)->encode($obj);
		};
		if($@)
		{
			$err = $@;
			AppCore::Common::print_stack_trace();
			warn __PACKAGE__.": Error encoding json: $err\n";
		}
		
		return $json;
	}
	
	sub x
	{
		my($x,$k,$v)=@_;
		#$x->{$k}=$v if defined $v;
		#$x->{$k};
		$x->set($k,$v) if defined $v;
		return $x->get($k);
	}
	
	sub AUTOLOAD 
	{
		my $node = shift;
		my $name = $AUTOLOAD;
		$name =~ s/.*:://;   # strip fully-qualified portion
		
		return if $name eq 'DESTROY';
		
		#print STDERR "DEBUG: AUTOLOAD() [$node] ACCESS $name\n"; # if $debug;
		return $node->x($name,@_);
	}

# Method: _init($inst,$ref)
# Private, only to be initiated by the using object instance
	sub _init
	{
		my $class = shift;
		my $inst = shift;
		my $column_name = shift || 'extra_data';
		
		my $json = $inst->get($column_name);
		my $self = bless {
			col	=> $column_name,
			data	=> _from_json( $json ? $json : '{}'),
			changed	=> 0,
			inst	=> $inst
		}, $class;
		
		#print STDERR "Debug: ".Dumper($self->{data});
		return $self;
		
	}
	
	sub hash { shift->{data} }

# Method: get($k)
# Return the value for key $k
	sub get#($k)
	{
		my $self = shift;
		my $k = shift;
		return $self->{data}->{$k};
	}

# Method: set($k,$v)
# Set value for $k to $v
	sub set#($k,$v)
	{
		my $self = shift;
		my ($k,$v) = @_;
		$self->{data}->{$k} = $v;
		$self->{changed}    = 1;
		return $self->{$k};
	}

# Method: is_changed()
# Returns true if set() has been called
	sub is_changed{ shift->{changed} }

# Method: update()
# Commits the changes to the instance object
	sub update
	{
		my $self = shift;
		my $json = _to_json($self->{data});
		my $col = $self->{col};
		$self->{inst}->set($col, $json);
		$self->{inst}->{$col} = $json;
# 		print STDERR "Debug: save '".$self->{inst}->$col."' on inst ".$self->{inst}."\n";
		return $self->{inst}->update;
	}
}
1;
