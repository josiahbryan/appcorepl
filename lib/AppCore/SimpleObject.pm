package AppCore::SimpleObject;
{
	use strict;
	
	sub new 
	{
		my $class = shift;
		my %args = @_;

		return bless { %args }, $class;
	}

	sub _accessor
	{
		my $x = shift;
		my $k = shift;
		if(@_)
		{
			$x->{$k} = shift;
		}

		$x->{$k};
	}
};
1;