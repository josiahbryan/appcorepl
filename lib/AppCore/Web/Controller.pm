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
		my $self = shift;
		if(!ref $self)
		{
			$SelfCache{$self} ||= {};
			$self = $SelfCache{$self};
		}
		
		$self->{_router} ||= AppCore::Web::Router->new(
			class	=> $self,
			stash	=> $self->stash,
		);
		
		return $self->{_router};
	}
};
1;

