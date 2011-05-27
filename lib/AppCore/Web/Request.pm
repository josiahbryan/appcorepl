use strict;
# Package: AppCore::Web::Request
# Very simple packaging of a "request" to a page.
# Not really an HTTP request, so much as a programatic request.
# This object offers three things:
# 1. by-name method access (via AUTOLOAD) to arguments (e.g. querystring variables)
# 2. $ENV{PATH_INFO} as a quasi-array through path(),next_path(),and shift_path()
# 3. Page URL accessor/setter through page_path()
package AppCore::Web::Request;
{
	use vars qw/$AUTOLOAD/;
	use Data::Dumper;
	
	sub new
	{
		my $class = shift;
		
		# If first arg is a hashref, deref it into a hash 
		@_ = %{$_[0]} if @_ == 1 && ref $_[0] eq 'HASH';
		
		my %args = @_;
		
		$args{PATH_INFO} ||= '/';
		
		my $self = bless \%args, $class;
		$self->path($args{PATH_INFO});
		
		# Page path is the url (Sans server) used to reach the current page, whereas
		# the PATH_INFO (or path()) is the arguments after the page_path().
		# e.g. if the user requests:
		# http://web/eas/oms/home/tasks/do?taskid=1
		# Hypothetically, 'oms' would be the EAS Module,
		# 'home/tasks' is what you would set page_path() to, 
		# and 'do' would be in PATH_INFO, while 'taskid'=>1 would be set as an AUTOLOAD'ed method
		$self->page_path('');
		
		return $self;
	}
	
	sub x
	{
		my($x,$k,$v)=@_;
		$x->{$k}=$v if defined $v;
		$x->{$k};
	}
	
	sub path 
	{
		my $self = shift;
		return @{$self->{_PATH_INFO}} if !@_;
		if(@_ > 1)
		{
			$self->{_PATH_INFO} = [@_];
			$self->{PATH_INFO} = join('/', @_);
		}
		else
		{
			my $v = shift;
			$self->{_PATH_INFO} = ref $v eq 'ARRAY' ? $v : [split/\//, $v];
			$self->{PATH_INFO} = join('/', @{$self->{_PATH_INFO}});
		}
		
			
		shift @{$self->{_PATH_INFO}} if !$self->{_PATH_INFO}->[0];
		
		return @{$self->{_PATH_INFO}};	
	}
	
	sub shift_path
	{
		my $self = shift;
		my @path = @{$self->{_PATH_INFO}};
		my $x = shift @path;
		$self->{_PATH_INFO} = \@path;
		$self->{PATH_INFO} = join('/', @path);
		#print STDERR "[DEBUG] shift_path(), x=$x, path_info=".$self->{PATH_INFO}."\n";
		return $x;
	}
	
	sub unshift_path
	{
		my $self = shift;
		my $path_elm = shift;
		my @path = @{$self->{_PATH_INFO}};
		unshift @path, $path_elm;
		$self->{_PATH_INFO} = \@path;
		$self->{PATH_INFO} = join('/', @path);
		#print STDERR "[DEBUG] shift_path(), x=$x, path_info=".$self->{PATH_INFO}."\n";
		return $path_elm;
	}
	
	
	sub next_path	{shift->{'_PATH_INFO'}->[0]}
	
	sub path_info { return @{shift->{'_PATH_INFO'}}; }

	
	sub AUTOLOAD 
	{
		my $node = shift;
		my $name = $AUTOLOAD;
		$name =~ s/.*:://;   # strip fully-qualified portion
		
		return if $name eq 'DESTROY';
		
		#print STDERR "DEBUG: AUTOLOAD() [$node] ACCESS $name\n"; # if $debug;
		return $node->x($name,@_);
	}
	
	sub push_page_path
	{
		my $self = shift;
		my $value = shift;
		
		
		#print STDERR "[DEBUG] push_page_path('$value') mark\n";
		return $value if !$value;
		
		$self->{_PAGE_PATH}||= [];
		
		#print STDERR "[DEBUG] push_page_path('$value') join of _PAGE_PATH before push: ".(join '/', @{$self->{_PAGE_PATH}})."\n";
		push @{$self->{_PAGE_PATH}}, $value;
		
		my $val = join '/', @{$self->{_PAGE_PATH}};
		
		#print STDERR "[DEBUG] push_page_path('$value') val='$val'\n";
		
		$self->page_path($val);
		
		return $value;
	}
	
	sub pop_page_path
	{
		my $self = shift;
		
		$self->{_PAGE_PATH}||= [];
		
		#print STDERR "[DEBUG] push_page_path('$value') join of _PAGE_PATH before push: ".(join '/', @{$self->{_PAGE_PATH}})."\n";
		my $pop_val = pop @{$self->{_PAGE_PATH}};
		
		my $val = join '/', @{$self->{_PAGE_PATH}};
		
		#print STDERR "[DEBUG] push_page_path('$value') val='$val'\n";
		
		$self->page_path($val);
		
		return $pop_val;
	}
	
	# Method: page_path($value=undef)
	# Page path is the url (Sans server) used to reach the current page, whereas
	# the PATH_INFO (or path()) is the arguments after the page_path().
	# e.g. if the user requests:
	# http://web/eas/oms/home/tasks/do?taskid=1
	# Hypothetically, 'oms' would be the EAS Module,
	# 'home/tasks' is what you would set page_path() to, 
	# and 'do' would be in PATH_INFO, while 'taskid'=>1 would be set as an AUTOLOAD'ed method
	sub page_path 
	{
		my $self = shift;
		my $value = shift;
		if(defined $value)
		{
			#AppCore::Common::print_stack_trace();
			#print STDERR "[DEBUG] page_path('$value'), app_root='".$self->app_root."'\n";
			$value =~ s/^\///;
			$self->{PAGE_PATH} = join '/', $self->app_root, $value;
			
			my @path = split /\//, $self->{PAGE_PATH};
			shift @path;
			$self->{_PAGE_PATH} = \@path;
		}
		my $p = $self->{PAGE_PATH};
		if(substr($p,-1) eq '/')
		{
			$p = substr($p,0,-1);
		}
		return $p;
	}
	
	sub last_path
	{
		my $self = shift;
		my @path = @{$self->{_PAGE_PATH} || []};
		return @path > 0 ? $path[$#path] : undef;
	}
	
	sub prev_page_path	
	{
		my $self = shift;
		my $how_far_back = shift || 1;
		my @path = @{$self->{_PAGE_PATH} || []};
		
		my $base = $self->app_root;
		if(@path && @path > 1)
		{
			return $base .'/' . join ('/', @path[ 0 .. $#path-$how_far_back]);
		}
		else
		{
			return $base;
		}
	}
	
	sub next_page_path	
	{
		my $self = shift;
		my @path = @{$self->{_PAGE_PATH} || []};
		
		return undef if !$self->next_path;
		
		my $base = $self->app_root;
		return $base .'/' . join ('/', @path, $self->next_path);
	}
	
	sub app_root
	{
		return '';
		#my $mod_name = eval 'AppCore::Module::MODULE_NAME()';
		#AppCore::Common->context->http_bin . ($mod_name ? '/'.$mod_name : '');
	}

}

1;
