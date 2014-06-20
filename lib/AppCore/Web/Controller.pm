package AppCore::Web::Controller;
{
	use strict;
	use AppCore::Web::Common;
	
	use base 'AppCore::SimpleObject';
	
	use AppCore::Web::Router;
	
	our %SelfCache = ();
	
	sub new 
	{
		my $class = shift;
		my %args = @_;
		
		return bless { %args }, $class;
	}
	
	sub stash
	{
		my $self = shift;
		my %args = @_;
		
		if(!ref $self)
		{
			$SelfCache{$self} ||= {};
			$self = $SelfCache{$self};
		}
		
		$self->{_stash} ||= AppCore::SimpleObject->new();
		if(scalar(keys %args) > 0)
		{
			$self->{_stash}->_accessor($_, $args{$_})
				foreach keys %args;
		}
		
		return $self->{_stash};
	}
	
	sub set_stash
	{
		my ($self, $stash, $merge_flag) = @_;
		
		if(!ref $self)
		{
			$SelfCache{$self} ||= {};
			$self = $SelfCache{$self};
		}
		
		if($merge_flag)
		{
			my $cur_stash = $self->stash;
		
			$stash->{$_} = $cur_stash->{$_}
				foreach keys %{$cur_stash || {}};
		}
		
		$self->{_stash} = $stash;
	}
	
	sub router
	{
		my $class = shift;
		my $self = $class;
		
		if(!ref $self)
		{
			$SelfCache{$class} ||= {};
			$self = $SelfCache{$class};
		}
		
		# Pass '$class' to the Router instead of '$self' because $self could be fake.
		# Router calls '->can' on $class, which works if $class is a string ('Foo::Bar')
		# or a blessed reference - but fails if its just a regular unblessed HASH,
		# which $self could be due to the previous block.
		$self->{_router} ||= AppCore::Web::Router->new($class);
		
		return $self->{_router};
	}
	
	sub setup_routes
	{
		# TODO: Reimplement in subclass
	}
	
	sub output
	{
		my $class = shift;
		
		return if ! $class->stash->{r};
		
		$class->stash->{r}->output(@_);
	}
	
	sub output_data
	{
		my $class = shift;
		
		return if ! $class->stash->{r};
		
		$class->stash->{r}->output_data(@_);
	}
	
	sub request
	{
		my $class = shift;
		
		return $class->stash->{req};
	}
	
	sub redirect
	{
		my $class = shift;
		my $url   = shift;
		die "No 'r' object in class->stash'" if !$class->stash->{r};
		#die Dumper $url;
		return $class->stash->{r}->redirect($url);
	}
	
	sub url_up
	{
		my $class = shift;
		my $count = shift;
		
		die "No request in class stash (stash->{req} undef)"
			if ! $class->stash->{req};
			
		my $url = $class->stash->{req}->prev_page_path($count);
		
		return $url;
	}
	
	sub url
	{
		my $class = shift;
		my $count = shift;
		
		die "No request in class stash (stash->{req} undef)"
			if ! $class->stash->{req};
			
		my $url = $class->stash->{req}->page_path;
		
		return $url;
	}

	sub redirect_up
	{
		my $class = shift;
		my $count = shift;
		
		@_ = %{ shift || {} } if ref $_[0] eq 'HASH';
		my %args = @_;
		
		die "No request in class stash (stash->{req} undef)"
			if ! $class->stash->{req};
		die "No 'r' object in class->stash'"
			if !$class->stash->{r};
		
		# Get the URL as of $count paths ago
		# E.g. if URL was /foo/bar/boo/baz, and $count=2, then 
		# $url would be /foo/bar
		my $url = $class->stash->{req}->prev_page_path($count);
		
		# Add the %args as ?key=value&key2=value2 pairs
		$url .= '?' if scalar(keys %args) > 0;
		$url .= join('&', map { $_ .'='. url_encode($args{$_}) } keys %args );
		
		# Send redirect to browser
		return $class->stash->{r}->redirect($url);
	}
	
	sub dispatch
	{
		my ($class, $req, $r) = @_;
		
		$class->stash(
			req	=> $req,
			r	=> $r,
		);
		
		$class->setup_routes
			if !$class->router->has_routes;
		
		warn $class.'::dispatch: No routes setup in router(), nothing to dispatch'
			if !$class->router->has_routes;
		
		$class->router->dispatch($req);
	}
	
	sub add_breadcrumb
	{
		my $class = shift;
		my @crumb_args = @_;
		
		return Content::Page::Controller->current_view->breadcrumb_list->push(@_);
	}
	
};
1;

