package AppCore::Web::Controller;
{
	use strict;
	use AppCore::Web::Common;
	
	use base 'AppCore::SimpleObject';
	
	use AppCore::Web::Router;
	
	my %SelfCache = {};
	
	sub new 
	{
		my $class = shift;
		my %args = @_;
		
		#die Dumper \%args;
		
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
		else
		{
			#die "No stash args: ".AppCore::Common::get_stack_trace();
		}
		
		return $self->{_stash};
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
};
1;

