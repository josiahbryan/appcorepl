package AppCore::Web::Controller;
{
	use strict;
	use AppCore::Web::Common;

	use base 'AppCore::SimpleObject';

	use AppCore::Web::Router;

	# For output_json()
	use JSON qw/encode_json/;

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
		# NOTE: Reimplement in subclass

		my $class = shift;
		print_stack_trace();
		warn __PACKAGE__.": You need to reimplement 'setup_routes()' in the '$class' class";
	}

	sub output
	{
		my $class = shift;

		my $r = $class->stash->{r};

		if(!$r)
		{
			print_stack_trace();
			warn __PACKAGE__.": output: Unable to output anything because no 'r' in stash";

			return undef;
		}

		$r->output(@_);
	}

	sub output_data
	{
		my $class = shift;

		my $r = $class->stash->{r};

		if(!$r)
		{
			print_stack_trace();
			warn __PACKAGE__.": output_data: Unable to output anything because no 'r' in stash";

			return undef;
		}

		$r->output_data(@_);
	}

	# I found myself repeatedly calling output_data
	# just to output json, so I added this as a shortcut
	sub output_json
	{
		my $class = shift;
		my $val   = shift;
		my $json  = undef;

		eval {
			$json = ref $val ? encode_json($val) : $val;
		};

		if($@)
		{
			use Data::Dumper;
			die "output_json: Error when getting json: $@, data: ".Dumper($val);
		}

# 		my $debug = 1;
#
# 		print STDERR "Controller: output_json: json: $json\n"
# 			if $debug;

		$class->output_data('application/json', $json);
	}

	sub request
	{
		my $class = shift;

		my $req = $class->stash->{req} || AppCore::Common->context->current_request;

		if(!$req)
		{
			print_stack_trace;
			die "No request in class stash (stash->{req} undef and no current_request)";
		}


		return $req;
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
			if ! $class->request;

		my $url = $class->request->prev_page_path($count);

		return $class->_url_with_args($url, @_);
	}

	sub url
	{
		my $class = shift;

		die "No request in class stash (stash->{req} undef)"
			if ! $class->request;

		my $url = $class->request->page_path;

		return $class->_url_with_args($url, @_);
	}

=pod
	_url_with_args($url, $path, ...)
		Returns $url appended with $path. Other args given are assumed to be key=>value pairs, unless the first arg is a HASHREF

		key=>value pairs (or the hashref) are expaneded and appended as ?key=value&key2=value2... to the $url (values are C<url_encode>d)

		Returns: String containing the new URL
=cut

	sub _url_with_args
	{
		my $class = shift;
		my $url   = shift;
		my $path  = shift;

		# Expand first hasref to a hash if present
		@_ = %{ shift || {} } if @_ == 1 && ref $_[0] eq 'HASH';
		my %args = @_;

		# Add $path as $url.'/'.$path`
		$url .= '/'  if substr($url,-1) ne '/' && substr($path,0,1) ne '/';
		$url .= $path;

		# Add the %args as ?key=value&key2=value2 pairs
		$url .= '?' if scalar(keys %args) > 0 && index($url,'?') < 0;
		$url .= join('&', map { $_ .'='. url_encode($args{$_}) } keys %args );

		# $url should now be "$url/$path?$key1=$value1&..."
		return $url;
	}

	sub redirect_up
	{
		my $class = shift;
		my $count = shift;

		@_ = %{ shift || {} } if ref $_[0] eq 'HASH';
		my %args = @_;

		die "No request in class stash (stash->{req} undef)"
			if ! $class->request;
		die "No 'r' object in class->stash'"
			if !$class->stash->{r};

		# Get the URL as of $count paths ago
		# E.g. if URL was /foo/bar/boo/baz, and $count=2, then
		# $url would be /foo/bar
		my $url = $class->request->prev_page_path($count);

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

	sub send_template
	{
		my ($class, $file, $in_view) = @_;

		$in_view = 1 if !defined $in_view;

		return sub {
			my ($class, $req, $r) = @_;
			my $path = $file =~ /\// ? $file : '../tmpl/'.$file;
			my $tmpl = $class->get_template($path);
			die "$class: No template found for $path." if !$tmpl || !ref $tmpl;

			my $key = $file;
			$key =~ s/\./_/g;
			if(!$in_view)
			{
				$tmpl->param('current_'.$key => 1);
				return $r->output_data("text/html", $tmpl->output);
			}

			$class->stash->{view}->tmpl_param('current_'.$key => 1);
			return $class->respond($tmpl->output);
		}
	}

	sub send_redirect
	{
		my ($class, $url) = @_;

		return sub {
			my ($class, $req, $r) = @_;
			my $final_url = $url;

			$final_url = $url->($class, $req, $r)
				if ref $url eq 'CODE';

			return $r->redirect($final_url);
		}
	}

	sub autocomplete_fkclause
	{
		my ($self, $validator, $static_fk_clause) = @_;
		#print STDERR __PACKAGE__.": autocomplete_fkclause: Need to override in subclass '$self', just returning static_fk_clause\n";
		return $static_fk_clause;
	}

	sub autocomplete_util
	{
		my ($class, $validator, $validate_action, $value, $r, $fk_clause, $disable_ranking) = @_;

		$fk_clause ||= '1=1';

		my $debug = 0;

		$r = $class->stash->{r} if !$r;

		$class->stash->{r} = $r
			if !$class->stash->{r};

		if(!$r)
		{
			print_stack_trace();
			warn __PACKAGE__.": autocomplete_util: Unable to output anything because no 'r' in stash";

			return undef;
		}

		print STDERR "Controller: autocomplete_util: validator: $validator, validate_action: $validate_action, value: $value\n"
			if $debug;

		my $ctype = 'text/plain';
		if($validate_action eq 'autocomplete')
		{
			my $clause = $class->autocomplete_fkclause($validator, $fk_clause) || $fk_clause;

			#print STDERR __PACKAGE__.": validate search: clause: $fk_clause ($clause)\n"
			#	if $debug;

			my $result = $validator->stringified_list(
					$value,
					$clause, #$fkclause
					undef, #$include_objects
					0,  #$start
					10, #$limit (both start and limit have to be defined, not undef - even if zero)
			);

			return $class->output_json([
				map {
					$_->{text} =~ s/,\s*$//g;
					{
						value => $_->{text},
						id    => $_->{id}
					}
				} @{ $result->{list} || [] }
			]);
		}
		elsif($validate_action eq 'search')
		{
			my $req = $class->request || {};

			my $clause = $class->autocomplete_fkclause($validator, $fk_clause) || $fk_clause;

			#print STDERR __PACKAGE__.": validate search: clause: $fk_clause ($clause)\n"
			#	if $debug;

			my $result = $validator->stringified_list(
					$value,
					$clause, #$fkclause

					0, #$include_objects

					$req->{start} || 0,  #$start
					$req->{limit} || 10, #$limit (both start and limit have to be defined, not undef - even if zero)

					0, # my $include_empty	= shift || 0;		# Include an empty option at the start?
					0, # my $debug		= shift || 0;		# Print debug info to stderr?
					$disable_ranking ? 0 : 1  # my $enable_ranking	= shift || 0;		# Enable sorting results based on ranking?
			);

			if(ref $result ne 'HASH')
			{
				return $class->output_json({
					total => 0,
					start => $req->{start} || 0,
					limit => $req->{limit} || 10,
					list  => []
				});
			}

			return $class->output_json({
				total => $result->{count},
				start => $req->{start} || 0,
				limit => $req->{limit} || 10,
				list  => [
					map {
						next if ref ne 'HASH';
						# Hack for "City, ST"
						#$_->{text} =~ s/, (\w{2})$/', '.uc($1)/segi;
						$_->{text} =~ s/,\s*$//g;
						{
							value => $_->{text},
							id    => $_->{id}
						}
					} @{ $result->{list} || [] }
				]
			});
		}
		elsif($validate_action eq 'validate')
		{
			my $clause = $class->autocomplete_fkclause($validator, $fk_clause) || $fk_clause;

			my $value = $validator->validate_string($value, $clause);
			my $ref = {
				value => $value,
				text  => $validator->stringify($value)
			};

			print STDERR "Controller: autocomplete_util: value: $value, ref: ".Dumper($ref)."\n"
				if $debug;

			return $class->output_json({ result => $ref, err => $@ });
		}
		elsif($validate_action eq 'stringify')
		{
			my $object = $validator->retrieve($value);
			my $ref = {};
			if($object)
			{
				$ref = {
					value	=> $object->id,
					text	=> $object->stringify
				}
			}
			else
			{
				$@ = "Object does not exist";
			}

			return $class->output_json({ result => $ref, err => $@ });
		}
		else
		{
			die "Unknown request type '$validate_action'";
			#error("Unknown Validation Request","Unknown validation request '$validate_action'");
		}
	}


};
1;
