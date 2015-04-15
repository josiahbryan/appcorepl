use strict;

=begin comment
	Package: AppCore::Web::Form
	
	Example Use of generate_stub_form:
		APPCORE_CONFIG=/opt/ncs.jbiconsult.com/conf/appcore.conf.pl perl -Mlib=www/appcore/lib -MAppCore::Common -Mlib=lib -MNCS::Patient -MAppCore::Web::Form -e 'print AppCore::Web::Form->generate_stub_form("NCS::Patient")'
	
	
	(For a complete example, see __DATA__, below - search for "## File" to see individual files.)
	
	Turns ...
	
		<f:form action="/save" method=POST" id="edit-form">
			<fieldset>
				<input bind="#driver.name">
				<input bind="#driver.customerid">
				<input type="submit" value="Save Name">
			</fieldset>
		</f:form>
	
	Into ...
		
		<form action=".." method="..">
			<table>
				<tr>
					<td>
						<label for="..">Customer:</label>
					</td>
					<td>
						<input id="edit-form-driver-customer" name="#driver.customerid" value="Trucking Company, Inc">
						<script>/*...lots of ajax stuff...*/</script>
					</td>
				</tr>
				<tr>
					<td>
						<label for="..">Name:</label>
					</td>
					<td>
						<input id="edit-form-driver-name" name="#driver.name" value="Bob Jones">
					</td>
				</tr>
				<tr>
					<td></td>
					<td>
						<input type=submit value="Save Name">
					</td>
				</tr>
			</table>
		</form>
		
	Via:
	
		my $tmpl = HTML::Template->new("file_containing_f:form_code.tmpl");
		
		my $html = AppCore::Web::Form->post_process($tmpl, {
			driver       => Driver::List->retrieve(234),
			validate_url => '/path/to/page/validate',
		});
		
		print $html;
		
	
	For the AJAX database validation:
	
	You just have to connect the '/path/to/page/validate' URL to  the method
	AppCore::Web::Form::validate_page and call it with $req and $r as the two arguments.
	
	If you're using the new 'AppCore::Web::Controller' as the base for your class,
	and you're using the AppCore::Web::Router object supplied from the controller,
	it's as simple as doing:
	
		$router->route('validate' => 'AppCore::Web::Form.validate_page');
	
	in your setup_routes() routine. Then the ::Router will call validate_page with the proper args.
	
=cut


package AppCore::Web::Form;
{
	use AppCore::Common;
	use AppCore::Web::Common;
	use AppCore::XML::SimpleDOM;
	use JSON qw/encode_json decode_json/;
	use Digest::MD5 qw/md5_hex md5_base64/;
	
	sub error
	{
		my ($title, $error) = @_;
		
		if(!$error && $title)
		{
			$error = $title;
			$title = "Error";
		}
		
		if(ref $error)
		{
			$error = "<pre>".Dumper($error,@_)."</pre>";
		}
		
		#exit;
		
		print STDERR "Error in form: $title: $error. Called from: ".called_from()."\n";
		
		print "Content-Type: text/html\r\n\r\n<html><head><title>$title</title></head><body><h1>$title</h1>$error<hr><p style='font-size:8px;color:#777'>".called_from()."</p></body></html>\n";
		exit -1;
	}
	
	
	sub uuid_to_field_meta
	{
		my $self = shift;
		my $uuid = shift;
		
		my $debug = 0;
		
		print STDERR "Form: validate_page: uuid: $uuid\n"
			if $debug;
		
		error("No UUID Given","To validate input, the URL must contain a UUID as the next path, or in a 'uuid' query argument")
			if !$uuid;
			
		my ($form_uuid, $class_obj_name, $class_key) = split /\./, $uuid;
		
		my $field_meta = AppCore::Web::Form::ModelMeta->by_field(uuid => $form_uuid);
		print STDERR "Form: validate_page: form_uuid: $form_uuid, class_obj_name: $class_obj_name, class_key: $class_key, field_meta: $field_meta\n" 
			if $debug;
		
		error("Invalid Form UUID","The form UUID '$form_uuid' in data does not exist in the database")
			if !$field_meta;
			
		my $hash = decode_json($field_meta->json);
		$hash ||= {};
		
		my $class_obj = undef;
		#my $class_key = undef;
		#my $class_obj_name = undef;
		
		my $bind_name = "#${class_obj_name}.${class_key}";
		
		#my $class_obj = $form_opts->{$class_obj_name} ||
		#		$hash->{$bind_name}->{class_name};
		my $class_obj = $hash->{$bind_name}->{class_name};
		
		print STDERR "Form: validate_page: bind_name: $bind_name, class_obj: $class_obj\n"
			if $debug;
			
		# Orignal object given was a hashref of args, so rely on stored data to create fake column meta
		if($class_obj eq 'HASH') 
		{
			my $field_data = $hash->{$bind_name};
			
			print STDERR "Form: validate_page: generating fake field meta, type: $field_data->{type}, linked: $field_data->{linked_class}\n"
				if $debug;
			
			return {
				type   => $field_data->{type},
				linked => $field_data->{linked_class},
			};
		}
		
		#die Dumper $hash;
		
		$class_obj = ref $class_obj ? ref $class_obj : $class_obj;
		error("Invalid field '$bind_name'","Cannot find '$bind_name' in form options or in stored form meta data") if !$class_obj;
		
		my $meta = eval '$class_obj->field_meta($class_key);';
		if($@)
		{
			print_stack_trace();
			die "Error in uuid_to_field_meta when resolving field meta for '$class_key': ".
				$@;
		}
		
		print STDERR "Form: validate_page: class_key: $class_key, meta: $meta\n"
			if $debug;
			
		error("No Meta for '$class_key'",
			"Unable to load metadata for column '$class_key' on object '$class_obj_name' ($class_obj)") if !$meta;
			
		return $meta;
	}
	
	# Note: You can provide a 'static_fk_constraint' in form_opts which will be appeneded to the fk_constraint loaded from the database meta
	sub validate_page
	{
		my $self = shift;
		my $req  = shift;
		my $r    = shift;
		
		# These next two opts must be set by overriding
		my $form_opts = shift || {};
		my $meta      = shift || undef;
		
		# Get UUID from request
		my $uuid = $req->next_path;
		$req->shift_path   if $uuid;
		$uuid = $req->uuid if !$uuid;
		
		# Resolve UUID to a database field
		$meta = $self->uuid_to_field_meta($uuid)
			if !$meta;
		
		my $debug = 0;
		
		my $validate_action = $req->next_path || 'validate';
		print STDERR "Form: validate_page: validate_action: $validate_action\n"
			if $debug;
			
		my $type = $meta->{type};
		print STDERR "Form: validate_page: meta type: $type\n"
			if $debug;
		
		if($meta->{linked})
		{
			$type = 'database';
			#$node->{class} = $meta->{linked}; #ref $class_obj ? ref $class_obj : $class_obj;
			#$node->{source} = $meta->{linked}.'.'.$meta->{linked}->primary_column;
		}
		elsif($type =~ /^enum/i)
		{
			my $str = $type;
			$str =~ s/^enum\(//g;
			$str =~ s/\)$//g;
			my @enum = split /,/, $str;
			s/(^'|'$)//g foreach @enum;
			
			#$node->{choices} = join ',', @enum;
			
			$type = 'enum';
		}
		elsif($type =~ /^varchar/i)
		{
			$type = 'string';
		}
		elsif($type =~ /^int/i)
		{
			$type = 'int';
		}
		
		if($type eq 'database')
		{
			my $value = $req->value || $req->term;
			print STDERR "Form: validate_page: type=database: value: $value, fk_constraint: '$meta->{fk_constraint}'\n" #.Dumper($meta)
				if $debug;
			
			return AppCore::Web::Controller->autocomplete_util(
				$meta->{linked},
				$validate_action,
				$value,
				$r,
				($meta->{fk_constraint} || '1=1').' and '.($form_opts->{static_fk_constraint} || '1=1'));
		}
		else
		{
			#error("No Server-Side Validation","No server-side validation available for data type '$type' on field $bind_name");
			error("No Server-Side Validation","No server-side validation available for data type '$type' on UUID $uuid");
		}
		
	}
	
	sub store_values
	{
		my $self = shift;
		my $req = shift;
		my $form_opts = shift;
		my $meta_objs = shift || {};
		
		my $uuid = $req->{'AppCore::Web::Form::ModelMeta.uuid'};
		error("Unable to Find Form UUID","Cannot find 'AppCore::Web::Form::ModelMeta.uuid' in posted data")
			if !$uuid;
		
		my $field_meta = AppCore::Web::Form::ModelMeta->by_field(uuid => $uuid);
		
		error("Invalid Form UUID","The 'AppCore::Web::Form::ModelMeta.uuid' in posted data does not exist in the database")
			if !$field_meta;
		
		my $hash = decode_json($field_meta->json);
		$hash ||= {};
		
		#die Dumper $hash;
		
		my $result_hash = {};
		
		my $class_obj_refs = {};
		
		foreach my $ref (keys %{ $hash })
		{
			my $cached_data = $hash->{$ref};
			my $class_obj = undef;
			my $class_key = undef;
			my $class_obj_name = undef;
			my $meta_obj = undef;
			
			my $req_val = $req->{$ref};
			
			if($ref =~ /^#(.*?)\.(.*?)$/)
			{
				$class_obj_name = $1;
				$class_key = $2;
				
				# Find the referenced data storage object from the option hash given.
				# For example, if $ref is '#filter.termid', $form_opts should have a key called 'filter'
				# that points to either a HASH ref ({}) or an AppCore::DBI-derived object
				$class_obj = $form_opts->{$class_obj_name};
				error("Invalid bind '$ref'","Cannot find '$class_obj_name' in options given to store_values()")
					if !$class_obj;
				
				# In rare cases, the object given in $form_opts for 'filter' (for example), may be a simple hashref,
				# but you still want to load the metadata from an AppCore::DBI object that has a column with
				# the same name as $class_key (in our example above of '#filter.termid', the given AppCore::DBI
				# object is expected to have the column 'termid')
				$meta_obj  = $meta_objs->{$class_obj_name};
				
				my $linked_class = undef;
				my $meta_title   = undef;
				
				# Before we store the value given from the $req object for this field (Ex termid)
				# into the $class_obj, first we have to check to see if it's a "linked" value,
				# i.e. a foreign key to another AppCore::DBI object.
				# The "linked" indicator can come from the 'linked' field in the schema of the
				# AppCore::DBI object for $class_obj, or if $class_obj is a plain hashref,
				# then the 'linked' class name must have been specified in the XML definition
				# of the form (as the 'class' attribute for the input with a type='database')
				# Either way, we need to find a $linked_class (if any) and the $meta_title (title
				# of the $class_key - e.x. termid) for error messages
				my $tmp_obj = $meta_obj || $class_obj;
				if($tmp_obj && UNIVERSAL::isa($tmp_obj, 'AppCore::DBI'))
				{
					my $meta;
					eval {
						#print STDERR "Debug: \$meta_obj='$meta_obj', \$class_obj='$class_obj', \$class_key='$class_key'\n";
						$meta = $tmp_obj->field_meta($class_key);
					};
					$meta = {} if !$meta;
					
					$linked_class = $meta->{linked};
					$meta_title   = $meta->{title};
				}
				elsif($cached_data->{linked_class})
				{
					$linked_class = $cached_data->{linked_class};
					$meta_title   = AppCore::Common::guess_title($class_key);
				}
				
				# If the value is, in fact, a "linked" value AND the value looks like an
				# integer, then we go ahead and validate the value via the linked class
				# before storing it
				if($linked_class && $req_val !~ /^\d+$/)
				{
					my $err = undef;
					eval
					{
						$req_val = $linked_class->validate_string($req_val);
						$err = $@;
					};
					$@ = $err if !$@;
					if($@)
					{
						error("Error with $meta_title",
							"There was an error in what you typed for $meta_title:".
							"<h1 style='color:red'>$@</h1>".
							"<a href='javascript:void(window.history.go(-1))'>&laquo; Go back to previous screen</a>".
							"<br><br>");
					}
				}
				
				# By this point, the value the user provided has been validated (if linked),
				# so we're ready to store it. If the $class_obj for the $ref is a databse object,
				# we use the set() function and flag it for a one-time update() call (for speed),
				# but if $class_obj is a plain hashref, we just set the key directly
				if(UNIVERSAL::isa($class_obj, 'AppCore::DBI'))
				{
					if(defined $req_val)
					{
						eval
						{
							$class_obj->set($class_key, $req_val);
							
							# Used to update() below on $class_obj
							$class_obj_refs->{$class_obj_name} = $class_obj;
							
							print STDERR "$ref: Storing '$req_val'\n";
						};
						if($@)
						{
							error("Error getting value for '$ref'",
								"Unable to read '$class_key' on '$class_obj_name': <pre>$@</pre>");
						}
					}
					else
					{
						#error("Value Not Defined for $ref",
						#	"Value not defined for '$ref' in data posted to server")
						#	if !defined $req_val;
					}
				}
				elsif(ref $class_obj eq 'HASH')
				{
					$class_obj->{$class_key} = $req_val;
				}
				else
				{
					die "Object for '$class_obj_name' in form_opts is not a HASH or an AppCore::DBI";
				}
				
			}
# 			else
# 			{
# 				#$val = $form_opts->{$ref};
# 				$result_hash->{$ref} = $req_val;
# 				error("Invalid bind '$ref'",
# 					"Value for '$ref' not defined in options given to store_values()") if !defined $val;
# 			}

			$result_hash->{$ref} = $req_val;
			
		}
		
		# Update each $class_obj we touched just once for speed
		$_->update foreach values %$class_obj_refs;
		
		#error($result_hash);
		
		return $result_hash;
	}
	
	sub generate_stub_form
	{
		my $class = shift;
		my $cdbi_object = shift;
		
		my $meta = $cdbi_object->meta;
		#print Dumper $meta;
		
		my @edit_list = @{ $meta->{edit_list} || [] };
		if(!@edit_list)
		{
			@edit_list = map { $_->{field} } @{ $meta->{schema} || [] };
		}
		
		my $cdbi_class = ref $cdbi_object ? ref $cdbi_object : $cdbi_object;
		
		my $class_key = lc( $meta->{class_noun} || $cdbi_class );
		$class_key =~ s/:://g;
		
		my @xml;
		
		push @xml, "<f:form action='\%\%page_path\%\%/post' method='POST' id='edit-form' uuid='$cdbi_class'>\n";
		push @xml, "\t<table class='form-table'>\n";
		foreach my $field (@edit_list)
		{
			my $meta = $cdbi_object->field_meta($field);
			push @xml, "\t\t<row bind='#${class_key}.$field'/>\n"
				unless $meta->{auto};
		}
		push @xml, "\t\t<row>\n";
		push @xml, "\t\t\t<input type='submit' class='btn btn-primary' value='Save Changes'/>\n";
		push @xml, "\t\t\t<a style='color:rgba(0,0,0,0.5)'   href='javascript:void(window.history.go(-1))'>Cancel</a>\n";
		push @xml, "\t\t\t<a style='color:rgba(255,0,0,0.6)' href='\%\%page_path\%\%/delete' onclick='return confirm(\"Are you sure?\")'>Delete $meta->{class_noun}</a>\n";
		push @xml, "\t\t</row>\n";
		push @xml, "\t</table>\n";
		push @xml, "</f:form>\n";
		
		return join '', @xml;
	}
	
	sub post_process#($tmpl)
	{
		my $class = shift;
		my $tmpl = shift;
		#my $viz_style = lc( shift || 'html' );
		
		my $blob = ref $tmpl ? $tmpl->output : $tmpl;
		
		my $form_opts = shift || {};
		
		# For some reason, this regex (and the one at the end to replace the content)
		# was taking > 9 seconds (combined - this one 4.9 sec) on a 375K HTML file. 
		# Why?? Don't know. But using index and substr (as shown below) resulted in sub 30ms times (total)
		#my ($data) = $blob =~ /(<f:form.*>.*<\/f:form>)/si;
		
		my $tag_start = '<f:form';
		my $tag_end   = '</f:form>';
		my $idx_start = index($blob, $tag_start);
		my $idx_end   = index($blob, $tag_end);
		my $data_length = $idx_end - $idx_start + length($tag_end);
		my $data = substr($blob, $idx_start, $data_length);
		#print $data;
		#return;
		
		#error("No Data in Blob","No Data in Blob") if !$data;
		return $blob if length($data) < 3; # Cannot have a complete tag in less 3 characters
		#error(length($data));
		
		#error("Error in Blob","Error in blob: $@<br><textarea>$data</textarea>");
		
		my $output;
		eval
		{
			my $form = AppCore::Web::Form->new($data);
			#die Dumper $form->visual('extjs')->render;
			$output = $form->render($form_opts);
			
		};
		if($@)
		{
			error("Error in Blob","Error in blob: $@<br><textarea rows=10 cols=60>$data</textarea>");
		}
		#return $output unless $viz_style eq 'html';
		#error($output);
		#error("","<br><textarea rows=35 cols=150>$output</textarea>");
		
		# Using substr instead of the regex was MUCH faster for the search/replace
		#$blob =~ s/(<f:form.*>.*<\/f:form>)/$output/sgi;
		substr($blob, $idx_start, $data_length, $output);
		
		return $blob;
	}
	
	
	# Function: new($data)
	# Create a new AppCore::Form object and load the data from $data. $data can be either a file name or a blob of XML 
	sub new#($data=undef)
	{
		my $class = shift;
		my $data = shift;
		#my $vars = shift;
		
		my $self = bless {}, $class;
		#$self->load($data,$vars);
		$self->load($data);
		
		return $self;
	}
	
		
	# Function: load($file_or_xml,$vars={})
	# Parses the xml using <AppCore::XML::SimpleDOM>, runs any perl <script> blocks inside the form, and sets up the internal model <AppCore::Form::Model>.
	sub load#($file_or_xml,$vars={})
	{
		my $self = shift;
		my $data = shift || die "Usage: \$form->load(\$file_or_xml,[\$vars])";
		my $vars = shift;
		
		my $dom = ref $data ? $data : AppCore::XML::SimpleDOM->parse_xml($data);
		
		$self->{dom} = $dom;
		
		if(!$dom->{uuid})
		{
			$dom->{uuid} = 'form'.md5_hex($data);
			$dom->{uuid} =~ s/[^a-zA-Z0-9]//g;
		}
		

		$self->_run_scripts($dom);
		
		#error("",$self);
		
		#$self->{model} = $self->{dom}->{model} = AppCore::Form::Model->new($self->dom->model,$self,$vars);
		#$self->_parse_model($dom,$vars);
	}

	# Function: _run_scripts
	# Internal function that evals all the scripts in the DOM for this form.
	sub _run_scripts#($node=undef,@stack=())
	{
		my $self = shift;
		my $node = shift;
		my @stack = @_;
		
		foreach my $node (@{$node->children})
		{
			my $path = join '/', map {$_->node} (@stack,$node);
			if(lc $node->node eq 'script' && lc $node->language eq 'perl')
			{
				eval $node->value;
				error($path,"<pre>$@</pre>") if $@;
			}
			
			$self->_run_scripts($node,@stack,$node);
		}
	}

	# Function: dom
	# Returns the DOM (an <AppCore::XML::SimpleDOM> object) for this form
	sub dom   { shift->{dom}   }

# 	# Function: model
# 	# Returns the model (an <AppCore::Form::Model> object) for this form
# 	sub model { shift->{model} }
	
	sub render
	{
		my $self = shift;
		my $form_opts = shift;
		
		$self->{form_opts} = $form_opts;
		
		my $dom = $self->dom;
		
		$self->{field_meta} = {};
		
		my $html = $self->_render_html($dom);
		
		#error($self->{field_meta});
		
		my $json = encode_json($self->{field_meta});
		
		my $field_meta = AppCore::Web::Form::ModelMeta->find_or_create({
			uuid	=> $dom->{uuid},
		});
		
		if($field_meta->json ne $json)
		{
			$field_meta->json($json);
		}
		
		$field_meta->timestamp(scalar(date()));
		$field_meta->update;
		
		return $html;
	}
	
	sub _is_pairtab
	{
		my $parent = shift;
		return lc $parent->node eq 'fieldlist' || lc $parent->node eq 'table';
	}
	
	
	sub _check_acl 
	{
		my $acl = shift;
		my $user = AppCore::Common->context->current_user;
		
		# Defaults to TRUE if NO ACL
		# Defaults to FALSE if HAS ACL but NO USER
		# Otherwise, it checks $acl against $self->user
		return $acl ? ( $user ? $user->check_acl($acl) : 0 ) : 1;
	}


	sub _strip_nbsp
	{
		local $_ = shift;
		$_ eq ' ' ? '' : $_;
	}

	sub _convert_spaces_to_nbsp
	{
		local $_ = shift;
		#s/\t/&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;/g;
		s/\s{2}/&nbsp;&nbsp;/g;
		$_;
	}

	sub _convert_newline 
	{
		my $x = shift;
		$x =~ s/(\n|\\n)/<br>/gi;
		return $x;
	}

	sub _remove_quotes
	{
		my $x = shift;
		$x =~ s/["']//g; #'"
		$x;
	}

	sub _format_render
	{
		my $format = shift;
		my $data = shift;
		
		$data = '&nbsp;' if $data eq '' || !defined $data || $data eq ' ';
		
		#print STDERR "data=[$data]\n";
		
		return $data;
	}

	sub _translate_module_uri($)
	{
		my $uri = shift;
		if($uri =~ /^module:(.*)/)
		{
			my $mod = $1;
			#my @parts = split/\//, $mod;
			#my $mod = shift @parts;
			
			my $http_bin = AppCore::Common->context->http_bin;

			$uri = join '/', $http_bin, $mod; #@parts;
		}
		
		
		return $uri;
	}

	sub _quote($)
	{
		my $x = shift;
		$x =~ s/(['"])/\\$1/g;
		return "\"$x\""; #"
	}

	sub _entity_encode($)
	{
		my $x = shift;
		return encode_entities($x);
		
	}

	sub _translate_js_fcall($$)
	{
		my $code = shift;
		my $row = shift;
		$code =~ s/[f\$]\(["']([^'"]+)['"]\)/_quote($row->{$1})/segi; #'
	#	error("",$code);
		return $code;

	}

	sub _get_field($$)
	{
		my $model = shift;
		my $ref = shift;
		
		#eval '*$model::error = undef'; undef $@;
		
		my $val = $model->$ref;
		if(defined $val)
		{
			return $val; #->value;
		}
		else
		{
			$@ = "No Such Model Variable: '$ref'";
			return undef;
		}
	}

	sub _perleval2($)
	{
		local $_ = shift;
		$_ = eval($_);
		$_ = "## $@ ##" if $@;
		$_;
	}

	sub _perleval($)
	{
		local $_ = shift;
		s/{{perl:(.*?)}}/_perleval2($1)/segi;
		return $_;
	}

	sub _render_html
	{
		my $self = shift;
		my $node = shift;
		my $t = shift || "\t";
		
		my @stack = @_;
		
		my @html;
		
		my $form = $self->dom;

		my $DEBUG = 0;
		
		#print STDERR $t, "--> ".$node->node."\n";
		
		if(!$node->{id})
		{
			my $x = $form->{_id_counter} ++;
			$node->{id} = "node$x";
		}
		
		my $path;
		eval
		{
			$path = join '/', map {$_->node} (@stack,$node);
		};
		
		#print STDERR "$path\n";
		
		if($@)
		{
			AppCore::Common::print_stack_trace();
			error("Error Loading Stack",[ map { ref $_ ? "$_" : ref $_ } ( @stack, $node ) ] );	
		}
		
		
		if(lc $node->node eq 'f:form')
		{
			
			#print STDERR "Form Frag: ".$node->is_form_fragment."\n";
			my $FORM_TAG_NAME = lc $node->is_form_fragment eq 'true' || $node->is_form_fragment eq '1' || !$node->{attrs}->{action} ? 'div' : 'form';
			$self->{is_form_fragment} = 1 if $FORM_TAG_NAME eq 'div';
			
			push @html, $t, "\t<$FORM_TAG_NAME style='border:0;padding:0;background:0;margin:0' ";
			push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
			push @html, " name='$form->{id}' " if !$node->attrs->{name};
			push @html, " id='$form->{id}'" if !$node->{attrs}->{id};
			push @html, ">\n";
			
			push @html, $t, "\t\t<input type='hidden' name='AppCore::Web::Form::ModelMeta.uuid' value='$form->{uuid}'>\n" if $form->{uuid};
			
			my $tmpl = AppCore::Web::Common::load_template(
				AppCore::Config->get('WWW_DOC_ROOT').
				AppCore::Config->get('WWW_ROOT').
				'/tmpl/form-db-ajax.tmpl');
				
			push @html, $tmpl->output;
			
			foreach my $child ( @{$node->children} )
			{
				push @html, $self->_render_html($child,$t."\t\t",@stack,$node);
			}
			
			push @html, $t, "\t</". ($self->{is_form_fragment} ? 'div' : 'form').">\n";
			
			#$consumed = 1;
		}
		else
		{
			my $tt = $t;
			$tt =~ s/\t/    /g;
			my $name = lc $node->node;
			print STDERR $tt.$node->node."\n" if ($name ne '#text' || $node->value =~ /[^\s\n\r]/) && $DEBUG;
			
			#my $path = join('->',@stack,$node->node);
			
			my $consumed = 0;
			
			if($name eq '#comment')
			{
				push @html, $t, "<!--" . $node->value . "-->\n";
				$consumed = 1;
			}
			elsif($name eq '#text')
			{
				my $v = $node->value;
				if($v =~ /[^\s\n\r]/)
				{
					push @html, $t,$v,"\n";
				}
				$consumed = 1;
			}
# 			elsif($name =~ /^m:(.*)$/)
# 			{
# 				my $val = _get_field($model,$1);
# 				error("Error Reading Model at $path",$@) if $@;
# 				$val = $val->value || $val->default;
# 				push @html, $t, "<span id='$1'>$val</span>\n";
# 				
# 				$consumed = 1;
# 			}
			elsif($name =~ /^perl:(.*)$/)
			{
				my $val = eval($1);
				error("Error Parsing Perl at $path",$@) if $@;
				push @html, $t, "$val\n";
				
				$consumed = 1;
			}
			elsif($name eq 'hr')
			{
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				if($is_pairtab)
				{
					$consumed = 1;
					push @html, "$t<tr class='f-noborder'><td colspan='2'>";
					
					if($node->title)
					{
						push @html, "<div ";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, " class='f-hr-titled'>"._perleval($node->title)."</div>";
					}
					else
					{
						push @html, "<hr class='f-hr' ";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, '/>';
					}
					push @html, "</td></tr>\n";
				}
				else
				{
					$consumed = 1;
					if($node->title)
					{
						push @html, "$t<div ";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, " class='f-hr-titled'>"._perleval($node->title)."</div>\n";
					}
					else
					{
						push @html, "$t<hr class='f-hr' ";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, ">\n";			
					}
				}
			}
			elsif($name =~ /h[12345]/i)
			{
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				if($is_pairtab)
				{
					my $group = $node->group;
					$consumed = 1;
					push @html, "$t<tr class='f-noborder'><td colspan='2'>\n";
					push @html, $t, "\t<".$name. (keys %{$node->attrs} ? " " : "");
					push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
					push @html, '>';
					push @html, "<a name='$group'>" if $group;
					push @html, _perleval($node->value);
					push @html, "</a>" if $group;
					push @html, "</".$name.">\n";
					push @html, $t,"</td></tr>\n";
				}
				
			}
			elsif($name =~ /br/i)
			{
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				if($is_pairtab)
				{
					$consumed = 1;
					push @html, "$t<tr class='f-noborder'><td colspan='2'><br></td></tr>\n";
				}
				
			}
			elsif($name eq 'input' || $name eq 'row')
			{
				my $bootstrap_flag = $form->{'enable-bootstrap'} eq 'true' || $form->{'enable-bootstrap'} eq '1';
				
				my $bootstrap_form_control_class = $bootstrap_flag ? 'form-control' : '';
				
				#if(!$node->type && ($node->ref || $node->bind))
				if($name eq 'row' && !$node->bind)
				{
					my $parent = $stack[$#stack];
					my $is_pairtab = _is_pairtab($parent);
					
					
					my $can_wrap = undef;
					if($is_pairtab)
					{
						my $key = 'allow-label-wrap';
						my $val = lc $parent->$key;
						$can_wrap = ($val eq 'false' || (defined $val && !$val)) ? 0:1;
					}
					
					push @html, $t;
					
					my $wrap_class = $bootstrap_flag ? 'form-group' : 'form-row';

					#push @html, $is_pairtab ? "<tr class='f-panelrow'><td colspan=2>" : "<div>";
					push @html, $is_pairtab ? "<tr class='$wrap_class'>" : "<div class='$wrap_class'>", "\n";
					
					#$node->{label} = $node->{attrs}->{label} = $model_item->label if !defined $node->label;
					if(!$node->{label} && !$node->{ng}) # ng = no guess
					{
						my $bind_subname = $node->bind;
						$bind_subname =~ s/^\#[^\.]+\.//g;
						$node->{label} = $node->{attrs}->{label} = AppCore::Common::guess_title($bind_subname);
						$node->{placeholder} = $node->{label}
							if !$node->{placeholder};
					}
					#die Dumper $node->{label}.'[1]';
					
					my $empty_label = 0;
# 					if($node->label)
# 					{
						my $text = $node->label;
						$text=~s/(^\s+|\s+$)//g;
						
						if($text)
						{
							#push @html, '<td class="td-label" valign="top"'.(!$can_wrap?' nowrap':'').'>' if $is_pairtab;
							push @html, $t, '<td class="td-label" valign="top"'.(!$can_wrap?' nowrap':'').'>'."\n" if $is_pairtab;
							
							my $label_class = $node->{attrs}->{'label-class'} || '';
						
							push @html, $t."\t <label class='row-label $label_class' title=\"".encode_entities($node->label)."\">", 
								    _convert_newline($node->label), 
								    ':</label> ',
								    "\n";
								    
							push @html, $t.'</td>'."\n" if $is_pairtab;
						}
						else
						{
							$empty_label = 1;
							
							push @html, $t, '<td>&nbsp;</td>', "\n" if $is_pairtab;
						}
						
# 					}
# 					else
# 					{
 						push @html, $t, "<td>\n" if $is_pairtab;
# 					}
					
# 					if($node->bind)
# 					{
# 						push @html, $self->_render_html($node,$t,@stack,$parent);
# 					}
# 					
					foreach my $child (@{$node->children})
					{
						push @html, $self->_render_html($child,$t."\t",@stack,$node);
					}
					
					#push @html, $t, "</td>\n";
					
					push @html, $t, $is_pairtab ? "</td>\n$t</tr>" : "</div>";
					push @html, "\n";
					
					$consumed = 1;
				}
				elsif($node->bind)
				{
					my $ref = $node->ref || $node->bind;
					
					$ref = $node->input if $name eq 'row' && !$ref;
					
					
# 					my $model_item = _get_field($model,$ref);
# 					error("Error Reading Ref '$ref' at $path",$@) if $@;
# 					error("Error Loading Ref '$ref' at $path","Ref '$ref' is null or not a reference [$model_item]: <pre>".Dumper($model).'</pre>') if !ref $model_item;

					my $class_obj = undef;
					my $class_key = undef;
					my $class_obj_name = undef;
					
					#my $value_ref = shift;
					my $val;
					
					$self->{form_opts} ||= {};
					if($ref =~ /^#(.*?)\.(.*?)$/)
					{
						$class_obj_name = $1;
						$class_key = $2;
						
						$class_obj = $self->{form_opts}->{$class_obj_name};
						
						if(!$class_obj)
						{
							if($self->{form_opts}->{allow_undef_bind})
							{
								$val = undef;
							}
							else
							{
								#error($self->{form_opts});
								error("Invalid bind '$ref'","Cannot find '$class_obj_name' in options given to post_process() or render()");
							}
						}
						elsif(!ref $class_obj)
						{
							if($self->{form_opts}->{allow_undef_bind})
							{
								my $defaults = $self->{form_opts}->{defaults} || {};
								
								my $meta = $class_obj->field_meta($class_key);
								$val = $defaults->{$ref} ? $defaults->{$ref} : 
								       $meta ? $meta->{default} : undef;
								       
								#die Dumper $defaults, $val, $ref;
							}
							else
							{
								error("No object given for '$ref'","Found '$class_obj' in options given - but it's the string, not the a reference to a live object. You can set 'allow_undef_bind' to a true value in the options given to render() or you can pass a AppCore::DBI object");
							}
						}
						elsif(UNIVERSAL::isa($class_obj, 'AppCore::DBI'))
						{
							eval
							{
								#$value_ref = $class_obj->get($class_key);
								$val = $class_obj->get($class_key);
							};
							if($@)
							{
								error("Error getting value for '$ref'",
									"Unable to read '$class_key' on '$class_obj_name': <pre>$@</pre>");
							}
						}
						elsif(ref $class_obj eq 'HASH')
						{
# 							error({
# 								class_obj => $class_obj,
# 								class_key => $class_key
# 							});
							$val = $class_obj->{$class_key};
						}
						else
						{
							error("Error getting value for '$ref'",
								"Object in form_opts for '$class_obj_name' is a ".ref($class_obj)." but not a HASH or an AppCore::DBI object");
						}
						
						#$node->{class} = $class_key;
						#$node->{attrs}->{class} = $class_key;
					}
					else
					{
						$val = $self->{form_opts}->{$ref};
						error("Invalid bind '$ref'",
							"Value for '$ref' not defined in options given to post_process() or render()") if !defined $val;
					}
					
					$node->{value} = $val;
					
					#eval
					#{
					#$val = $model_item->value;
					#};
					#error("Error Loading Ref '$ref'","<pre>".$@->title.",".$@->text."</pre>");
					#$val = $model_item->default if !$val;
					
					# TODO: Load value from form opts
					
					$val = $node->default if !$val;
					
					#error("\$val",Dumper([$val,$node]));
					
					
					# TODO: Add f:form 'readonly' flag
					my $readonly = $node->readonly eq 'true' || $self->{form_opts}->{readonly} ? 2 : 0; # TODO: Why 2?
					
					#error($model_item->node,$readonly) if $model_item->node ne 'tax';
					
					my $label_id = join '.', $form->{id}, _remove_quotes($ref);	
					$label_id =~ s/#//g;
					$label_id =~ s/\./-/g;
				
				
					my $parent = $stack[$#stack];
					my $is_pairtab = _is_pairtab($parent);
					my $can_wrap = undef;
					if($is_pairtab)
					{
						my $key = 'allow-label-wrap';
						my $val = lc $parent->$key;
						$can_wrap = ($val eq 'false' || (defined $val && !$val)) ? 0:1;
					}
					
					my $already_has_label = 0;
					if($parent->node eq 'row' && $parent->label)
					{
						$already_has_label = 1;
					}
					
					
					push @html, $t;

					
					my $type = $node->type;
					
					if($class_obj &&
					   UNIVERSAL::isa($class_obj, 'AppCore::DBI'))
					{
						my $meta = $class_obj->field_meta($class_key);
						error("No Meta for '$class_key'",
							"Unable to load metadata for column '$class_key' on object '$class_obj_name' (".ref($class_obj).")") if !$meta;
							
						if(!$type)
						{
							$type = $meta->{type};
							
							if($meta->{linked})
							{
								$type = 'database';
								$node->{class}  = $meta->{linked}; #ref $class_obj ? ref $class_obj : $class_obj;
								$node->{source} = $meta->{linked}.'.'.$meta->{linked}->primary_column;
							}
							elsif($type =~ /^enum/i)
							{
								my $str = $type;
								$str =~ s/^enum\(//g;
								$str =~ s/\)$//g;
								my @enum = split /,/, $str;
								s/(^'|'$)//g foreach @enum;
								
								$node->{choices} = join ',', @enum
									if ! $node->{choices};
								
								$type = 'enum';
							}
							elsif($type =~ /^varchar/i)
							{
								$type = 'string';
							}
							elsif($type =~ /^int/i)
							{
								$type = 'int';
							}
						}
						
						if(!$node->label && !$already_has_label)
						{
							$node->{label} =
								$node->{attrs}->{label} = $meta->{label} || $meta->{title};
						}
						
						if(!$node->placeholder)
						{
							$node->{placeholder} =  
								$node->{attrs}->{placeholder} = $node->{label} || $meta->{label} || $meta->{title};
						}
					}
					
					#print STDERR "$path: $ref ($type) [$val]\n";
					
					
					$self->{field_meta}->{$ref} =
					{
						#class_obj_name => $class_obj_name,
						#class_key      => $class_key,
						class_name     => ref $class_obj ? ref $class_obj : $class_obj,
						linked_class   => $node->{class},
						type           => $type,
					};
					
					#error([$self->{field_meta}, $class_obj]);
					
					my $format = $node->format;
					my $length = $node->length || $node->size;
					#$length = $node->length if !$length;
					$length = 30 if $type =~ /database/ && $node->class && !$length;
					$length = 9 if $type =~ /(int|float|num)/ && !$length;
					#error("",[$length,$node->length,$node->length]) if $node->node eq 'title';
					my $render = lc $node->render || 'ajax_input';
					$render = 'select'   if $type eq 'enum' && $render ne 'radio';
					$type = 'bool' if $type eq 'int' && $length == 1;
					
					if($type eq 'enum' && $render eq 'select' && !$node->render)
					{
						my @choices = $node->options || split/,/, $node->choices;
						$render = 'radio' if @choices <= 2;
					}
					#die Dumper $node, $model_item, $render if $model_item->node eq 'customerid';
					#error("",[$length,$model_item->length,$node->length]) if $model_item->node eq 'title';
					

					my $hidden = $render eq 'hidden';
					
					my $rowid = 'tr.'.$label_id;
					$rowid =~ s/\./-/g;
					
					my $k_visb = "visual-border";
					my $v_visb = lc $node->$k_visb;
					my $vis_border = $v_visb eq 'true' || $v_visb eq '1';
					
					push @html, $is_pairtab ?
						"<tr id='$rowid' ".($vis_border ? "class='f-border'":"").">\n" :
						"<div class='form-input-group' id='$rowid' ".($vis_border ? "class='f-border'":"").">\n";
					
					my $empty_label = 0;
					
					if(!$already_has_label || $node->{label})
					{
						#$node->{label} = $node->{attrs}->{label} = $model_item->label if !defined $node->label;
						#$node->{label} = $node->{attrs}->{label} = AppCore::Common::guess_title($node->bind) if !$node->{label} && !$node->{ng}; # ng = no guess
						
						if(!$node->{label} && !$node->{ng}) # ng = no guess
						{
							my $bind_subname = $node->bind;
							$bind_subname =~ s/^\#[^\.]+\.//g;
							$node->{label} = $node->{attrs}->{label} = AppCore::Common::guess_title($bind_subname);
							$node->{placeholder} = $node->{label}
								if !$node->{placeholder};
						}
						#die Dumper $node->{label}.'[2]';
						
					
						if($node->label && $type ne 'bool')
						{
							
							my $text = $node->label;
							$text=~s/(^\s+|\s+$)//g;
							
							if($text)
							{
#								my $first_row_child = lc $parent->node eq 'row' && $node->id eq $parent->children->[0]->id;
								push @html, $t, "\t", '<td class="td-label" valign="top"'.(!$can_wrap?' nowrap':'').'>', "\n" if $is_pairtab;
								#push || $first_row_child;
								
								my $is_row_label = $node->node eq 'row';
								
								my $label_class = $node->{attrs}->{'label-class'} || '';
							
								push @html, $t, "\t\t", "<label for='$label_id' ",
									'class="'. ($is_row_label ? 'row-label' : '').' '.$label_class.'"',
									($render eq 'radio' ? "style='cursor:default !important'" : ''),
									" title=\"".encode_entities($node->label)."\"",
									'>', 
									_convert_newline($node->label), 
									':</label> ', "\n"  if !$hidden;
								push @html, $t, "\t", '</td>', "\n" if $is_pairtab; # || $first_row_child;
								#push @html, "\n$t<td>\n$t" if $first_row_child;
							}
							else
							{
								$empty_label = 1;
							}
							
						}
						
# 						$node->{placeholder} = 
# 							$node->{attrs}->{placeholder} =
# 								$node->{label}
# 									if !$node->{placeholder} && !$node->{ng}; # ng = no guess
					}
					else
					{
# 						$node->{placeholder} = 
# 							$node->{attrs}->{placeholder} =
# 								AppCore::Common::guess_title($node->bind)
# 									if !$node->{placeholder} && !$node->{ng}; # ng = no guess
					}	
					
# 					error("Error",{
# 						already_has_label => $already_has_label,
# 						html => encode_entities(join('',@html))
# 					}) if $ref eq '#driver.comments';

					#error($node) if $ref eq '#patient.state';
					
					#error($model_item->node,{length=>$length,type=>$type,format=>$format}) if $model_item->node eq 'parentopcode';
					
					my $hint = $node->hint;
					my $hint_pos_key  = "hint-position";
					my $hint_pos_key2 = "hint-pos";
					
					my $hint_pos = $node->$hint_pos_key || $node->$hint_pos_key2;
					
					if($hint_pos =~ /^[-+]\d+/)
					{
						$hint_pos = $hint_pos < 0 ? 'above' :
							    $hint_pos > 0 ? 'below' : 
							    '';
					}
					
					my $suffix = $node->suffix;
					my $prefix = $node->prefix;

					push @html, $t, "\t", '<td class="td-input"'.($empty_label ? ' colspan="2"':'').'>' if $is_pairtab; # && !$hidden;
					
					if($hint && ($hint_pos eq 'above' || $hint_pos eq 'top'))
					{
						$hint = text2html($hint, 1);
						push @html, "<span class='hint'>$hint</span><br>" if !$hidden;
					}
					
					
					if($readonly)
					{
						my $class  = $node->class;
						#my $source = $node->source;
						my $val_stringified = $val;
						
						#my $class = ref $class_obj ? ref $class_obj : $class_obj;
						
						if($class && ref $val_stringified) #$render eq 'ajax_input' && $class)
						{
							#error("Ajax Input Not Implemented","Error in $path: Ajax Input not implemented yet.");
							
							#if(!$class)
							#{
							#	error("No AppCore::DBI Class Given","No AppCore::DBI Class given at path '$path' for ajax_input database model item, bind: $ref");
							#}
							$val_stringified = $val_stringified->stringify if UNIVERSAL::isa($val_stringified, $class);
						}
							
							
						push @html, $t."\t $prefix<b><span class='f-input-readonly text ".($node->class?$node->class.' ':'')."' id='$label_id' "
							.($format ? "f:format="._quote($format)." ":"")
							.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
							.">".$val_stringified."</span></b>".($suffix ? "<label for='$label_id' class='form-input-suffix'>$suffix</label>" : ""). 
							($readonly == 2 ? "<input type='hidden' name='$ref' value='".encode_entities($val)."' id='out.$label_id'/>" : "");
					}
					elsif($type eq 'text')
					{
						my $rows = $node->rows || 10;
						my $cols = $node->cols || 40;
						push @html, $t."\t <textarea"
							." name='$ref'"
							." id='$label_id'"
							." rows=$rows"
							." cols=$cols"
							." class='text form-input ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."'>"
							.$val
							."</textarea>";
						
						# Disabling for now due to IExplore bug
						#push @html, "<script>\$('#$label_id').ext = new Ext.form.TextArea({applyTo:'$label_id',grow:true});</script>" if $self->{_extjs} && !$extjs_disable;
					}
					elsif($type eq 'database' || $type eq 'enum')
					{
						my $class  = $node->class;
						my $source = $node->source;
						
						#my $class = ref $class_obj ? ref $class_obj : $class_obj;
						
						if($render eq 'ajax_input')
						{
							#error("Ajax Input Not Implemented","Error in $path: Ajax Input not implemented yet.");
							
							if(!$class)
							{
								error("No AppCore::DBI Class Given","No AppCore::DBI Class given at path '$path' for ajax_input database model item");
							}
							
							#my $class  = $node->class;
							#my $source = $node->source;
							
							my $val_stringified = $val;
							my $clause = '';
# 							if($source)
# 							{
# 								error("Invalid source name","Invalid source '$source'") if $source !~ /^((?:\w[\w\d]+::)*\w[\w\d]+)\.([\w\d_]+)$/;
# 								my ($source_class,$source_column) = ($1,$2);
# 								
# 								error("$path","$source_class can't field_meta() [mark1: class=$class,source=$source, ref=$ref]")       if !$source_class->can('field_meta');
# 			
# 								my $meta = $source_class->field_meta($source_column);
# 								error("$path","$source_class didn't give any meta for $source_column (source='$source')") if !$meta;
# 								
# 								$clause = $meta->{link_clause} if $meta && $meta->{link_clause} && $meta->{link_clause} !~ /={{/;
# 								error("$path","Invalid characters in '$clause'")   if $clause && $clause =~ /(;|--)/;
# 							}
							
							#my $ret = $class->validate_string($val_stringified,$clause);
							#if(!$ret)
							#{
							#	$val_stringified = $class->stringify($val);
							#}
							
							$val_stringified = $val_stringified->stringify if UNIVERSAL::isa($val_stringified, $class);
							
							#die Dumper $val, $val_stringified, $ret if $label_id eq 'SearchForm.related_to';
							
							{
		
								
								push @html, $t."\t $prefix",
									"<div style='display:inline' f:db_class='$class' id='${label_id}_error_border'>",
										"<input name='$ref' type='".($render eq 'hidden' ? 'hidden' : 'text')."' "
											.($length ? "size=$length ":"")
											.($node->placeholder ? "placeholder='".$node->placeholder."'":"")
											.($format ? "f:format="._quote($format)." ":"")
											.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
											."class='text $bootstrap_form_control_class f-ajax-fk ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."'"
											.($val_stringified?" value='".encode_entities($val_stringified)."'":'')
											." "
											.($readonly ? 'readonly' : "")
											." id='$label_id'/>",
									"</div>",
									($suffix ? "<label for='$label_id' class='form-input-suffix'>$suffix</label>\n" : "");
									
								my $noun = eval '$class->meta->{class_noun}' || "Linked Record";
								
								if(!$self->{form_opts}->{validate_url})
								{
									error("No Validate URL Given","No 'validate_url' in options given to render() - required for an 'ajax_input' database option, found on ${ref}.");
								}
								
								my $url = $self->{form_opts}->{validate_url};
								#$url .= '/' if $url !~ /\/$/;
								#$url .= $form->{uuid};
								my $uuid = $form->{uuid};
								my $bind_uuid = join('.', $uuid, $class_obj_name, $class_key);
								if($uuid =~ /\./)
								{
									error("Invalid Form UUID",
										"The UUID you used with your form ($uuid) won't work for AJAX validation of database values (relevant field: $ref) because the validator encodes the Form UUID with the field bind into a string seperated by '.' (example: $bind_uuid) - and your UUID contains a '.' - choose a different UUID or use render='select' on '$ref'");
								}
								
								push @html, "<script>",
									"\$(function() { var hookFunction = window.databaseLookupHook;",
									"if(typeof(hookFunction) == 'function')",
										"hookFunction(\$('#${label_id}'),'$url', '$bind_uuid');",
									"});</script>";
								
								# Search btn
								#/linux-icons/Bluecurve/16x16/stock/panel-searchtool.png
								#my $root = '/appcore'; # AppCore::Common->context->http_root;
								#push @html, $t,qq{\t<img src="$root/images/silk/page_find.png" width=16 height=16 style="cursor:hand;cursor:pointer" onclick='ajax_do_search(event,"$label_id","$class","$source","$noun")' align='absmiddle' title="Search for a $noun">\n};
								
								if($class)
								{
# 									if(_check_acl($class->meta->{create_acl}))
# 									{
# 										# New btn
# 										push @html, $t,qq{\t<img src="$root/images/silk/page_add.png"  width=16 height=16 style="cursor:hand;cursor:pointer" onclick='ajax_fknew(event,"$label_id","$class","$source")' align='absmiddle' title="New $noun">\n};
# 									}
									
# 									# Edit btn
# 									#/linux-icons/Bluecurve/16x16/stock/stock-edit.png
# 									my $disp = $val && (ref $val ? eval '$val->id' : 1) ? 'default' : 'none';
# 									
# 									if(_check_acl($class->meta->{edit_acl}) || _check_acl($class->meta->{read_acl}))
# 									{
# 										#error("[$disp]","val=$val") if $node->node eq 'statusid';
# 										push @html, $t,qq{\t<img src="$root/images/silk/page_edit.png" width=16 height=16 style="cursor:hand;cursor:pointer;display:$disp" onclick='ajax_fkedit(event,"$label_id","$class","$source")' align='absmiddle' title="View/Edit $noun" id="ajax_edit_btn_$label_id">\n};
# 									}
								}
								
								# Progress/Error icon
								#push @html, $t,"\t<img style='display:none;cursor:default' width=16 height=16 id='ajax_verify_output_$label_id' align='absmiddle' title='Checking data...'>";
								
								#push @html, $t,"\t<script>setTimeout(function(){ajax_verify(\$('#$label_id'),\"$class\",\"$source\")},1000)</script>\n";
							}
							
							
							
							# Disabling for now because I don't like ForeignKeyField's handling of drop down with valid value, hit show all, red underline - neeed to polish, make more usable.
# 							if(0 && $self->{_defined_ext22})
# 							{
# 								push @html, "$prefix<div style='display:inline' f:db_class='$class' id='${label_id}_error_border'><input name='$ref' type='".($render eq 'hidden' ? 'hidden' : 'text')
# 									.($length ? "size=$length ":"")
# 									.($format ? "f:format="._quote($format)." ":"")
# 									.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
# 									."class='text f-ajax-fk ".($self->{_extjs} ? "x-form-text x-form-field" : "")." ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."'"
# 									.($val_stringified?" value='".encode_entities($val_stringified)."'":'')
# 									." "
# 									#.($readonly ? 'readonly' : "")
# 									." id='$label_id' onfocus='select()'/></div>".($suffix ? "<label for='$label_id'>$suffix</label>" : "")."\n";
# 									
# 								my $noun = eval '$class->meta->{class_noun}' || "Linked Record";
# 								my $can_create = _check_acl($class->meta->{create_acl}) ? 'true' : 'false';
# 								my $can_read = _check_acl($class->meta->{edit_acl}) || _check_acl($class->meta->{read_acl}) ? 'true' : 'false';
# 								my $can_qc = $class->meta->{quick_create} && $class->check_acl($class->meta->{create_acl}) && ($class->can('can_create') ? $class->can_create : 1)  ? 'true':'false';
# 								
# 								push @html, "<script>Ext.onReady(function(){";
# 								push @html, "new Ext.app.ForeignKeyField({applyTo:'$label_id',";
# 								push @html, "className:'$class',";
# 								push @html, "sourceName:'$source',";
# 								push @html, "canQuickCreate:$can_qc,";
# 								push @html, "canCreate:$can_create,";
# 								push @html, "canEdit:$can_read,";
# 								push @html, "classNoun:'$noun',";
# 								push @html, "emptyText:'Enter a ".lc($noun)."'})})</script>\n";
# 							}
# 							else
# 							{
# 		
# 								
# 								push @html, "$prefix<div style='display:inline' f:db_class='$class' id='${label_id}_error_border'><input name='$ref' type='".($render eq 'hidden' ? 'hidden' : 'text')."' "
# 									.($length ? "size=$length ":"")
# 									.($format ? "f:format="._quote($format)." ":"")
# 									.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
# 									."class='text f-ajax-fk ".($self->{_extjs} ? "x-form-text x-form-field" : "")." ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."'"
# 									.($val_stringified?" value='".encode_entities($val_stringified)."'":'')
# 									." "
# 									#.($readonly ? 'readonly' : "")
# 									." id='$label_id' onkeydown='ajax_verify(this,\"$class\",\"$source\")' onfocus='select()'/></div><label for='$label_id'>$suffix</label>\n";
# 									
# 								my $noun = eval '$class->meta->{class_noun}' || "Linked Record";
# 								# Search btn
# 								#/linux-icons/Bluecurve/16x16/stock/panel-searchtool.png
# 								my $root = '/appcore'; # AppCore::Common->context->http_root;
# 								push @html, $t,qq{\t<img src="$root/images/silk/page_find.png" width=16 height=16 style="cursor:hand;cursor:pointer" onclick='ajax_do_search(event,"$label_id","$class","$source","$noun")' align='absmiddle' title="Search for a $noun">\n};
# 								
# 								if($class)
# 								{
# 									if(_check_acl($class->meta->{create_acl}))
# 									{
# 										# New btn
# 										push @html, $t,qq{\t<img src="$root/images/silk/page_add.png"  width=16 height=16 style="cursor:hand;cursor:pointer" onclick='ajax_fknew(event,"$label_id","$class","$source")' align='absmiddle' title="New $noun">\n};
# 									}
# 									
# 									# Edit btn
# 									#/linux-icons/Bluecurve/16x16/stock/stock-edit.png
# 									my $disp = $val && (ref $val ? eval '$val->id' : 1) ? 'default' : 'none';
# 									
# 									if(_check_acl($class->meta->{edit_acl}) || _check_acl($class->meta->{read_acl}))
# 									{
# 										#error("[$disp]","val=$val") if $node->node eq 'statusid';
# 										push @html, $t,qq{\t<img src="$root/images/silk/page_edit.png" width=16 height=16 style="cursor:hand;cursor:pointer;display:$disp" onclick='ajax_fkedit(event,"$label_id","$class","$source")' align='absmiddle' title="View/Edit $noun" id="ajax_edit_btn_$label_id">\n};
# 									}
# 								}
# 								
# 								# Progress/Error icon
# 								push @html, $t,"\t<img style='display:none;cursor:default' width=16 height=16 id='ajax_verify_output_$label_id' align='absmiddle' title='Checking data...'>";
# 								
# 								push @html, $t,"\t<script>setTimeout(function(){ajax_verify(\$('#$label_id'),\"$class\",\"$source\")},1000)</script>\n";
# 							}

							
							
						}
						elsif($render eq 'radio')
						{
							error("Cannot Render Database as Radio","Error in $path: Cannot render a database model item as a radio button") if $type eq 'database';
							
							my @list;
							my $auto_hint = 1;
							my $hint_column;
							
							my $val = $node->value  || $node->default;
							if($node->options)
							{
								my @opts = @{$node->options};
								foreach my $o (@opts)
								{
									my $x = $o->value;
									my $v = $o->data || $o->valueid;
									
									#$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
									$v = $x if $v eq '';
									push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
								}
							}
							else
							{
								my @choices = split/,/, $node->choices;
								foreach my $c (@choices)
								{
									my ($v,$x) = $c =~ /^([^=]+)?=?(.*)$/;
									$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
									push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
								}
							}
							
							#@list = map {{text=>$_,valueid=>$_,selected=>$_ eq $val}} @choices;
							$auto_hint = 0;
							#error("Choices",Dumper(\@list,$val));
							
							push @html, "\n";
							push @html, $t, "$prefix" if $prefix;
							push @html, $t, "\t<div class='radio-group'>\n";
							foreach my $op (@list)
							{
								my $radio_id = $label_id.'_'._entity_encode(_remove_quotes($op->{valueid}));
								
								#"onchange='\$(\"hint_$label_id\").innerHTML=this.options[this.selectedIndex].getAttribute(\"f:hint\");FormMgr.fieldChanged(this.getAttribute(\"f:bind\"),this.value)' onkeypress='var t=this;setTimeout(function(){t.onchange()},5)'";
								
								push @html, 
									"$t\t\t".
									"<div class='radio' onclick='\$(\"#$radio_id\").get(0).checked=true;\$(\"#$radio_id\").change()' style='cursor:pointer'><input style='cursor:pointer' type='radio' name='$ref' value="
									._quote(_entity_encode($op->{valueid}))
									.($hint_column ? " f:hint="._quote(_entity_encode($op->{hint})) : "")
									.($op->{selected} ? " checked":"")
									." id='$radio_id'"
									." onchange='\$(\"#$label_id\").val(this.value);var elm=\$(\"#hint_$label_id\");if(this.getAttribute(\"f:hint\")) {elm.html(this.getAttribute(\"f:hint\").show())}else{elm.hide()}' "
									." onkeypress='var t=this;setTimeout(function(){t.onchange()},5)'"
									."><label for='$radio_id' style='cursor:pointer'> "
									._convert_spaces_to_nbsp(_entity_encode(_convert_newline($op->{text})))
									."</label>"
									.($op->{selected} ? "<script>setTimeout(function(){\$('#$radio_id').change()},5);</script>" : "")
									."</div>\n";
							}
							
							push @html, $t,"\t</div>\n";
							
							#onchange='FormMgr.fieldChanged(this.getAttribute(\"f:bind\"),this.value)' 
							#push @html, $t, "\t<input type='hidden' value='".encode_entities($val)."' id='$label_id'/>\n";
							
							push @html, $t, "\t<label for='$label_id' class='form-input-suffix'>$suffix</label>\n" if $suffix;
							push @html, $t, "\t<br>\n" if $auto_hint && $hint_pos eq 'below';
							push @html, $t, "\t<span class='hint' id='hint_$label_id' style='display:none'></span>\n";
							push @html, $t, "\t<script>setTimeout(function(){\$('#$label_id').change()},5);</script>\n";
							
							if($self->{_extjs})
							{
							#	push @html, "<script>\$('#$label_id').ext = new Ext.form.ComboBox({typeAhead: true,triggerAction: 'all',transform:'$label_id',forceSelection:true});</script>";
							}
							
							#error("",\@html);
						}
						elsif($render eq 'select')
						{
# 							my $live_filter = $node->filter;
# 							my ($lv_other_item,$lv_other_itemid, $lv_other_attr, $lv_my_attr, $lv_other_noun, $lv_my_noun);
# 							
# 							if($live_filter)
# 							{
# 								if($live_filter =~ /^(\w+)\.(\w+)=(\w+)$/)
# 								{
# 									$lv_other_itemid = $1;
# 									$lv_other_attr = $2;
# 									$lv_my_attr    = $3;
# 								}
# 								elsif($live_filter =~ /^(\w+)\.(\w+)$/)
# 								{
# 									$lv_other_itemid = $1;
# 									$lv_other_attr = $2;
# 									$lv_my_attr    = $2;
# 								}
# 								elsif($live_filter =~ /^(\w+)$/)
# 								{
# 									$lv_other_itemid = $1;
# 									$lv_other_attr = $1;
# 									$lv_my_attr    = $1;
# 								}
# 								else
# 								{
# 									error("Invalid 'filter' Attribute","Error in $path: 'filter' attribute '$live_filter' is not correctly formatted.");
# 								}
# 								
# 								$lv_other_item = _get_field($model,$lv_other_itemid);
# 								error("Error in 'filter' Attribute - Can't read Other Item '$lv_other_itemid' at $path",$@) if $@;
# 								error("Error in 'filter' Attribute - Can't read Other Item '$lv_other_itemid' at $path","Ref '$lv_other_itemid' is null or not a reference [$node]: <pre>".Dumper($model).'</pre>') if !ref $node;
# 								
# 								# Todo: right now, we're only going to use the primary key of $lv_other_itemid to simplify logic.
# 								# If we get more fancy and want to use another column other than the prikey of $lv_other_itemid (e.g. $lv_other_attr != the other prikey),
# 								# then we'll have to somehow tell the rendering function for $lv_other_item that it needs to include $lv_other_attr in the html output for
# 								# the javascript on the client to use for filtering. 
# 								# Therefore, we're going to ignore $lv_other_attr for now
# 								
# 								my $text = $node->label;
# 								$text=~s/(^\s+|\s+$)//g;
# 								$lv_my_noun = $node->label;
# 									
# 								$lv_other_noun = $lv_other_item->label;
# 								$lv_other_noun = AppCore::Common::guess_title($lv_other_itemid) if !$lv_other_noun; # ng = no guess;
# 							}
							
							
							
							my @list;
							my $auto_hint = 1;
							my $hint_column;
							if($type eq 'database')
							{
								my $key = $node->key; # || error("No Key","No key given to bind for $path");
								my $text = $node->text; # || error("No Text","No text given to bind for $path");
								$hint_column = $node->hint || undef;
								my $table = $node->table;
								my $clause = $node->clause || '1';
								my $orderby = $node->orderby;
								my $db = $node->db;
								
								my $class = $node->class;
								my $source = $node->source;
								# 103289pa, 1pc
								
								if($class && !$class->can('get_stringify_sql'))
								{
									error("$path","$class can't get_stringify_sql()");
								}
								
								if($class)
								{
									$text = $class->get_stringify_sql;
									$orderby = $class->get_orderby_sql if $class->can('get_orderby_sql');
									$key = $class->primary_column;
									$table = $class->table;
									$db = $class->meta->{db};
									
									#die Dumper $db,$class->db_Main->{Name} if $table eq 'program';
								}
								
								$orderby = $text if !$orderby;
								
								#die Dumper $class;
								#error([$class,$source]);
								
								
								if($source)
								{
									error("Invalid source name","Invalid source '$source'") if $source !~ /^((?:\w[\w\d]+::)*\w[\w\d]+)\.([\w\d_]+)$/;
									my ($source_class,$source_column) = ($1,$2);
									
									error("$path","$source_class can't field_meta() [mark2: class=$class,source=$source, ref=$ref]")       if !$source_class->can('field_meta');
				
									my $meta = $source_class->field_meta($source_column);
									error("$path","$source_class didn't give any meta for $source_column") if !$meta;
									
									$clause = $meta->{link_clause} if $meta && $meta->{link_clause} && $meta->{link_clause} !~ /={{/;
									error("$path","Invalid characters in '$clause'")   if $clause && $clause =~ /(;|--)/;
								}
								
								error("No Key","No key given to bind for $path") if !$key;
								error("No Text","No text given to bind for $path") if !$text;
								
								#print STDERR "Debug: field ".$node->node.": text=$text, clause=$clause, orderby=$orderby (class=$class,source=$source)\n";
								
								my $hint_limit_key = 'max-hint-length';
								my $hint_len = $node->$hint_limit_key;
								my $hint_key = $hint_len && $hint_len =~ /^\d+$/ ? "concat(substr($hint_column,1,$hint_len),if(length(`$hint_column`)>$hint_len,'...',''))" : "`$hint_column`";
								
								#my $lv_my_attr_key = $lv_my_attr ? "`$lv_my_attr`" : "";
								#($lv_my_attr_key?",$lv_my_attr_key as `lv_attr`":'')."
								
								my $sql = "select `$table`.`$key` as `valueid`,$text as `text`".($hint_column?",$hint_key as `hint`":'')." from `$table` where ($clause) order by $orderby";
								#error("",$sql);
								my $q_get = AppCore::DBI->dbh($db)->prepare($sql);
								$q_get->execute();
								
								push @list, {valueid=>'-',text=>'(Unknown/NA)',hint=>''};
								push @list, $_ while $_ = $q_get->fetchrow_hashref;
								
								if($class->can('form_format_hint_text'))
								{
									$_->{hint} = $class->form_format_hint_text($_->{hint},$_) foreach @list;
								}
								
								my $value = $node->value || $node->default;
								
								my $got_sel = 0;
								foreach my $item (@list)
								{
									if($item->{valueid} eq $value)
									{
										$got_sel = 1;
										$item->{selected} = 1;
									}
								}
								
								if(!$got_sel && $value)
								{
									foreach my $item (@list)
									{
										if($item->{text} eq $value)
										{
											$got_sel = 1;
											$item->{selected} = 1;
										}
									}
								}
								
								#die "<pre>".Dumper(\@list,$node->value)."</pre>";
							}
							else
							{
								#my $val = $node->value  || $node->default;
								#my @choices = split/,/, $model_item->choices;
								##@list = map {{text=>$_,valueid=>$_,selected=>$_ eq $val}} @choices;
								#foreach my $c (@choices)
								#{
								#	my ($v,$x) = $c =~ /^([^=]+)?=?(.*)$/;
								#	$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
								#	push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
								#}
								
								my $val = $node->value  || $node->default;
								#error("",[$val, $node, $node]);
								if($node->options)
								{
									my @opts = @{$node->options};
									foreach my $o (@opts)
									{
										my $x = $o->value;
										my $v = $o->data || $o->valueid;

										#$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
										$v = $x if $v eq '';
										push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
									}
									
									# die "Xx";
								}
								else
								{
									my @choices = split/,/, $node->choices;
									foreach my $c (@choices)
									{
										my ($v,$x) = $c =~ /^([^=]+)?=?(.*)$/;
										$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
										push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
									}
								}


								$auto_hint = 0;
							}
							#error("",Dumper(@list));
							
							
							
							push @html, "$prefix"
								."<select"
								." name='$ref'"
								." f:model_item_class='$class'"
								." class='".($node->class?$node->class:'')."'"
								." id='$label_id'"
								." onkeypress='var t=this;setTimeout(function(){t.onchange()},5)' ";
							
							push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
							push @html, ">\n".
								(join("\n",
									map { "$t\t".
										"<option value="
										._quote(_entity_encode($_->{valueid}))
										.($hint_column ? " f:hint="._quote(_entity_encode($_->{hint})) : "")
										#.($lv_my_attr ? " f:lv_attr="._quote(_entity_encode($_->{lv_attr})) : "")
										.($_->{selected} ? " selected":"")
										.">"
										._entity_encode($_->{text})
										."</option>" 
									} @list))
								."\n$t</select>\n";
								
							
							if($type eq 'database')
							{
								my $root   = '/appcore'; #AppCore::Common->context->eas_http_root;
								my $noun   = eval '$class->meta->{class_noun}' || "Linked Record";
								# Edit btn
								#/linux-icons/Bluecurve/16x16/stock/stock-edit.png
								#die "labelid=$label_id, val=$val <pre>".Dumper($val)."</pre>" if ref $val && $val !=10 ;
								my $disp = $val && (ref $val ? eval '$val->id' : 1) ? 'default' : 'none';
								#$@ = undef;
								if($class)
								{
									if(_check_acl($class->meta->{edit_acl}))
									{
										push @html, $t,qq{<img src="$root/images/silk/page_edit.png" width=16 height=16 style="cursor:hand;cursor:pointer;display:$disp" onclick='ajax_fkedit(event,"$label_id","$class","$source")' align='absmiddle' title="View/Edit $noun" id="ajax_edit_btn_$label_id">\n};
									}
		
									# New btn
									if(_check_acl($class->meta->{create_acl}))
									{
										# New btn
										push @html, $t,qq{<img src="$root/images/silk/page_add.png"  width=16 height=16 style="cursor:hand;cursor:pointer" onclick='ajax_fknew(event,"$label_id","$class","$source")' align='absmiddle' title="New $noun">\n};
									}
								}
								
# 								push @html, $t,qq|<script>setTimeout(function(){
# 										\$('#$label_id').oldAjaxFkSelectOnchange = \$('#$label_id').onchange;
# 										\$('#$label_id')._ajax_fk_select_onchange = _ajax_fk_select_onchange;
# 										\$('#$label_id').onchange = function(evt)
# 										{
# 											if(elm.oldAjaxFkSelectOnchange) {
# 												\$('#$label_id').oldAjaxFkSelectOnchange();
# 											}
# 											\$('#$label_id')._ajax_fk_select_onchange(evt);
# 										};
# 										\$('#$label_id').onchange()
# 									},5);</script>\n|;

							}
# 							elsif($self->{_extjs} && !$extjs_disable)
# 							{
# 								push @html, $t,"<script>\$('#$label_id').ext = new Ext.form.ComboBox({typeAhead: true,triggerAction: 'all',transform:'$label_id',forceSelection:true});</script>\n";
# 							}
							
							push @html, "$t<label for='$label_id' class='form-input-suffix'>$suffix</label>" if $suffix;
							push @html, ($auto_hint && $hint_pos eq 'below' ? "<br>" : "")
									."<span class='hint' id='hint_$label_id' style='display:none'></span>";
						}
					}
					elsif($render eq 'div' || $render eq 'span')
					{
						my $nn = $render eq 'div' ? 'div' : 'span';
						push @html, "$t\t $prefix<$nn "
							.($format ? "f:format="._quote($format)." ":"")
							.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
							."class='".($node->class ? $node->class.' ':'')."' "
							."id='$label_id'"
							.($val?">".encode_entities($val)."</$nn>":'>')
							.($suffix ? "<label for='$label_id' class='form-input-suffix'>$suffix</label>" : "");
					}
					elsif($type eq 'range')
					{
						my $min = $node->min || 0;
						my $max = $node->max || 100;
						my $step = $node->step || 10;
						
						push @html, "$prefix<select data-type='range' "
							." name='$ref'"
							." id='$label_id'"
							." class='form-input ".($node->class?$node->class.' ':'').($readonly?' readonly ':'')."' ";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, ">\n";
						
 						my $last_step = 0;
 						my $cur_step  = 0;
 						push @html, "$prefix\t<option>-</option>\n";
 						for ($cur_step = $min; $cur_step <= $max; $cur_step += $step)
 						{
 							my $selected = $val > $last_step && $val <= $cur_step ? ' selected' : '';
 							push @html, "$prefix\t<option${selected}>$cur_step</option>\n";
 							$last_step = $cur_step;
 						}
						
						push @html, "</select>";
						
						# Disabling for now due to IExplore bug
						#push @html, "<script>\$('#$label_id').ext = new Ext.form.TextArea({applyTo:'$label_id',grow:true});</script>" if $self->{_extjs} && !$extjs_disable;
					}
					elsif($type eq 'bool')
					{
						push @html, "$prefix<input type='checkbox' "
							." name='$ref'"
							." id='$label_id'"
							." ".($val ? "checked" : "")
							." value='1' "
							." class='form-input ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."' ";#>\n";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, ">\n";
							
						if(!$already_has_label && $node->label)
						{
							my $text = $node->label;
							$text=~s/(^\s+|\s+$)//g;
							
							if($text)
							{
								my $is_row_label = $node->node eq 'row';
								
								my $label_class = $node->{attrs}->{'label-class'} || '';
							
								push @html, $t, "\t\t", "<label for='$label_id' ",
									'class="'. ($is_row_label ? 'row-label' : '').' '.$label_class.'"',
									($render eq 'radio' ? "style='cursor:default !important'" : ''),
									" title=\"".encode_entities($node->label)."\"",
									'>', 
									_convert_newline($node->label), 
									'</label> ', "\n"  if !$hidden;
							}
						}	
						# Disabling for now due to IExplore bug
						#push @html, "<script>\$('#$label_id').ext = new Ext.form.TextArea({applyTo:'$label_id',grow:true});</script>" if $self->{_extjs} && !$extjs_disable;
					}
					else # All other rendering types (string, etc)
					{
						#push @html, "$prefix<div style='display:inline'><input name='$ref' type='".($render eq 'hidden' ? 'hidden' : 'text')."' f:bind='$label_id' "
						push @html, $t."\t $prefix<input name='$ref' type='".($render eq 'hidden' ? 'hidden' : 
								$node->{attrs}->{'type-hint'} ? $node->{attrs}->{'type-hint'} : 'text')."' "
							.($length ? "size=$length ":"")
							.($node->placeholder ? "placeholder='".$node->placeholder."' ":"")
							.($format ? "f:format="._quote($format)." ":"")
							.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
							."class='text $bootstrap_form_control_class ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."'"
							.($val?" value='".encode_entities($val)."' ":'')
							.' ';
							
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } grep { !/^(readonly|type-hint|size|length|placeholder|class|value)/ } keys %{$node->attrs});
							#.($readonly ? 'readonly' : "")
						push @html," id='$label_id'/>".($suffix ? "<label for='$label_id' class='form-input-suffix'>$suffix</label>" :"")."\n";

						unless($hidden)
						{
							my $x_type = "x-type";
							$x_type = $node->$x_type;
							$type = $x_type if $x_type;
							$type = $node->xtype if $node->xtype;
							#die Dumper $type,$node if $ref eq 'datelogged';
							
							if($type eq 'fraction')
							{
								#push @html, "<script>\$('#$label_id').ext = new Ext.ux.form.FractionField({applyTo:'$label_id'});</script>" if $extjs_enabled;
							}
							elsif($type eq 'date')
							{
								#push @html, "<script>\$('#$label_id').ext = new Ext.ux.form.DateTime({applyTo:'$label_id',dateFormat:'Y-m-d',timeFormat:'H:i:s'});var field=\$('#$label_id');field.name='$ref';field.style.display='none';</script>";
								
								#push @html, "<script>\$('#$label_id').ext = EAS.Data.XType.Date.applyTo('$label_id')</script>";
								
								my $jquery = qq`
								
								\$(function() {
									\$( "#${label_id}" ).datepicker({
										showOn: "both",
										buttonImage: window.CALENDAR_ICON ? window.CALENDAR_ICON : "http://jqueryui.com/resources/demos/datepicker/images/calendar.gif",
										buttonImageOnly: true,
										dateFormat: "yy-mm-dd",
									});
								});
								
								`;
								
								push @html, "<script>$jquery</script>";
								
							}
							elsif($type eq 'datetime')
							{
								#push @html, "<script>\$('#$label_id').ext = new Ext.ux.form.DateTime({applyTo:'$label_id',dateFormat:'Y-m-d',timeFormat:'H:i:s'});var field=\$('#$label_id');field.name='$ref';field.style.display='none';</script>";
								
								#push @html, "<script>\$('#$label_id').ext = EAS.Data.XType.DateTime.applyTo('$label_id')</script>";
								
								my $jquery = qq`
								
								\$(function() {
									\$( "#${label_id}" ).datepicker({
										showOn: "both",
										buttonImage: window.CALENDAR_ICON ? window.CALENDAR_ICON : "http://jqueryui.com/resources/demos/datepicker/images/calendar.gif",
										buttonImageOnly: true,
										dateFormat: "yy-mm-dd",
									});
								});
								
								`;
								
								push @html, "<script>$jquery</script>";
							}
							elsif($type eq 'number')
							{
								#push @html, "<script>\$('#$label_id').ext = new Ext.form.NumberField({applyTo:'$label_id'});</script>" if $extjs_enabled;
							}
							elsif($type eq 'float')
							{
								#push @html, "<script>\$('#$label_id').ext = new Ext.form.NumberField({applyTo:'$label_id',allowDecimals:true});</script>" if $extjs_enabled;
							}
							elsif($type eq 'integer')
							{
								#push @html, "<script>\$('#$label_id').ext = new Ext.form.NumberField({applyTo:'$label_id',allowDecimals:false});</script>" if $extjs_enabled;
							}
							elsif($type =~ /^custom:(.*)/)
							{
								#my $xtype_class = $1;
								#push @html, "<script>\$('#$label_id').ext = ${xtype_class}.applyTo('$label_id')</script>";
							}
							else
							{
								#push @html, "<script>\$('#$label_id').ext = new Ext.form.TextField({applyTo:'$label_id'});</script>" if $extjs_enabled;
							}

						};
						
						
					}
					
					if($hint && $hint_pos ne 'above')
					{
						$hint = text2html($hint, 1);
						push @html, ($hint_pos eq 'below' ? '<br>': '') . "<span class='hint'>$hint</span>"; # .($is_pairtab ? "" : "<br>");
					}
					
					
# 					push @html, "\n$t<script>FormMgr.regField('$label_id',\$('#$label_id'))</script>";
# 					my $calc = $node ? $node->calculate : undef;
# 					push @html, "\n$t<script>\$('#$label_id').calculate = function(mgr){FormMgr.setBindPrefix("._quote($model->id)."); return $calc};</script>\n" if $calc;
# 					
# 					if(!$hidden)
# 					{
# 						push @html, "\n$t<script>var e=\$('#$label_id');if(e) e.onkeyup=function(){FormMgr.fieldChanged(this.getAttribute('f:bind'),this.value)};".
# 						($val ? "setTimeout(function(){\$('#$label_id').onkeyup();/*debug('$label_id initalized')*/},100)" : "").
# 							#"setTimeout(function(){\$('#$label_id').onkeyup();debug('$label_id initalized')},10)".
# 						#	"if(\$('#$label_id').ext){\$('#$label_id').ext.addListener('change',\$('#$label_id').onkeyup);".
# 						#	                       "\$('#$label_id').ext.addListener('keyup',\$('#$label_id').onkeyup);}".
# 									"</script>\n" if !$readonly;
# 						#push @html, $is_pairtab ? "$t</td></tr>\n" : "$t<br/>\n";
# 					}
					
					push @html, "$t" . ($is_pairtab ? "</td></tr><!--/.end input-group [pairtab]-->\n" : "</div><!--/.end input-group [div]-->\n");
					$consumed = 1;
				}
			}
			elsif($name eq 'panel')
			{
				my $lay = $node->layout;
				
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				push @html, $t, "<tr class='f-panelrow'><td colspan=2>" if $is_pairtab;
				
				my $old_t = $t;
				$t .= "\t";
				
				if($lay eq 'columns')
				{
					push @html, $t, "<table cellspacing=0 class='f-panel ".$node->class."' border=0 ".($node->width ? 'width='.$node->width : '')."><tr>\n";
					
					foreach my $child (@{$node->children})
					{
						push @html, $self->_render_html($child,$t."\t",@stack,$node);
					}
					
					push @html, $t, "</tr></table>\n";
				
				}
				else
				{
					my $parent = $stack[$#stack];
					
					my $l_col = 0;
					if(lc $parent->layout eq 'columns' && lc $parent->node eq 'panel')
					{
						$l_col = 1;
					}
					
					push @html, $t, "<td valign='top'>\n" if $l_col;
					
					if($node->title)
					{
						push @html, $t, "<fieldset class='f-panel ".$node->class."'><legend>".$node->title."</legend>\n";
					}
					else
					{
						push @html, $t, "<div class='f-panel ".$node->class."'>\n";
					}
					
						
					foreach my $child (@{$node->children})
					{
						push @html, $self->_render_html($child,$t."\t",@stack,$node);
					}
					
					if($node->title)
					{
						push @html, $t, "</fieldset>\n";
					}
					else
					{
						push @html, $t, "</div>\n";
					}
					
					push @html, $t, "</td>\n" if $l_col;
				}
				
				push @html, $old_t, "</td></tr>" if $is_pairtab;
				
				$consumed = 1;
			}
			elsif($name eq 'fieldlist')
			{
				my $id = $node->id;
				push @html, $t, "<table cellspacing=0 class='f-fieldlist ".$node->class."' border=0 ".($id?"id='$id'":'')." ".($node->width ? 'width='.$node->width : '').">\n";
				
				foreach my $child (@{$node->children})
				{
					push @html, $self->_render_html($child,$t."\t",@stack,$node);
				}
				
				push @html, $t, "</table>\n";

				$consumed = 1;
			}
			elsif($name eq 'column')
			{
				if(@stack <= 1)
				{
					#push @html, "## C1: Must use tag 'column' inside a panel with layout type 'columns' ##";
					error("Layout Error at $path","C1: Must use tag 'column' inside a panel with layout type 'columns'");
				}
				else
				{
					my $parent = $stack[$#stack];
					if(lc $parent->node ne 'panel')
					{
						#push @html, "## C2: Must use tag 'column' inside a panel (".$parent->node.") ##";
						error("Layout Error at $path","C2: Must use tag 'column' inside a panel (".$parent->node.")");
					}
					elsif(lc $parent->layout ne 'columns')
					{
						#push @html, "## C3: Parent 'panel' must have layout type 'columns' ##";
						error("Layout Error at $path","C3: Parent 'panel' must have layout type 'columns'");
					}
					else
					{
						$consumed = 1;
						
						push @html, $t, "<td valign='top' class='f-column' ".($node->style ? 'style="'.$node->style .'"' : '')." ".($node->width ? 'width='.$node->width : '').">\n";
						if($node->title)
						{
							push @html, $t, "<fieldset><legend>".$node->title."</legend>\n";
						}
						
						foreach my $child (@{$node->children})
						{
							push @html, $self->_render_html($child,$t."\t",@stack,$node);
						}
						
						if($node->title)
						{
							push @html, $t, "</fieldset>\n";
						}
						
						push @html, $t, "</td>\n";
					}
				}
			}
# 			elsif($name eq 'submit')
# 			{
# 				if($self->{is_form_fragment})
# 				{
# 					warn "Not including SUBMIT in a form fragment - do it yourself";
# 				}
# 				else
# 				{
# 					my $method = uc $node->method || 'GET';
# 					my $uri = $node->uri;
# 					my $label = $node->label;
# 					
# 					# Conditionally translates URIs like 'module:forms/echo?x=1' to appros URLs for this EAS instance
# 					$uri = _translate_module_uri($uri);
# 					
# 					if($model->data_override && $model->data_override->{post_url})
# 					{
# 						$uri = $model->data_override->{post_url};
# 					}
# 					
# 					my $parent = $stack[$#stack];
# 					my $is_pairtab = _is_pairtab($parent);
# 						
# 					if($self->{_buttonbar})
# 					{
# 						push @html, "<script>Ext.onReady(function(){\n";
# 						push @html, "var currentForm=\$('".$model->id."');currentForm.setAttribute('method','$method');currentForm.setAttribute('action','$uri');\n";
# 						push @html, "PCI.ButtonBar.addButton({icon:'Save',text:'$label',handler:function(){FormMgr.preprocess_form();\$('".$model->id."').submit();}});\n";
# 						push @html, "PCI.ButtonBar.addButton({icon:'Cancel',text:'Cancel',handler:function(){window.history.go(-1);},side:'right'});\n";
# 						push @html, "});</script>";
# 						
# 						
# 					}
# 					else
# 					{
# 						push @html, $t;
# 						push @html, "<tr><td>&nbsp;</td><td>" if $is_pairtab;
# 						
# 						if(!$model->is_readonly)
# 						{
# 							push @html, "<button ";
# 				#			class="form-ctrl"
# 							push @html, "class='form-ctrl ".($node->class?$node->class:'')."' ";
# 							push @html, "onclick='FormMgr.submit(this,\$(\"".$model->id."\"))' f:method='$method' f:uri='$uri'";
# 							push @html, ">";
# 							push @html, $label;
# 							
# 							my @children = @{$node->children};
# 							foreach my $child (@children)
# 							{
# 								push @html, $self->_render_html($child,$t."\t",@stack,$node);
# 							}
# 							
# 							push @html, "</button><script>".qq|
# 								setTimeout(function(){
# 									var f=\$('|.$model->id.qq|');
# 									f.setAttribute('method','$method');
# 									f.setAttribute('action','$uri');
# 									f.onsubmit=function(){FormMgr.preprocess_form()}
# 								},100);
# 							|."</script>";
# 						}
# 						
# 						my $can_reset = lc $node->can_reset;
# 						#error("",$can_reset);
# 						$can_reset = $can_reset eq 'true' || $can_reset eq '1' ? 1:0;
# 						
# 						push @html, "<a href='javascript:window.history.go(-1)' class='form-ctrl f-submit-reset-link noprint'>Return to the previous page without making any changes</a>" if $can_reset;
# 						
# 						push @html, "</td></tr>" if $is_pairtab;
# 						
# 						push @html, "\n";
# 					}
# 				}
# 				
# 				$consumed = 1;
# 			}
# 			
			if(!$consumed)
			{
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				next if $is_pairtab && lc $node->node eq 'br';
				
				my $name = lc $node->node;
				
				## Wierd Bug here - need to investigate
	#			$name = 'h1' if $name eq 'label';
				
				push @html, $t, "<".$name. (keys %{$node->attrs} ? " " : "");
				push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});


				if($name eq 'br' || $name eq 'input')
				{
					push @html, ">\n";
				}
				elsif(@{ $node->children })
				{
					push @html, ">\n";
					foreach my $child (@{$node->children})
					{
						push @html, $self->_render_html($child,$t."\t",@stack,$node);
					}
					push @html, $t, "</".$name.">\n";
				}
				elsif(($node->value && !$node->{attrs}->{value}) || $name eq 'script' || $name eq 'style')
				{
					push @html, '>';
					push @html, _perleval($node->value) unless $node->src;
					push @html, "</".$name.">\n";
				}
				else
				{
					#push @html, $name eq 'textarea' ? '></textarea>' : "/>\n";
					push @html, "></".$name.">\n";
				}
			}
			
		}
		
		#print STDERR "$path [end]\n";
		
		return join '', @html;
	}


};

package AppCore::Web::Form::ModelMeta;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta(
	{
		#database	=> 'eas',
		table		=> 'form_model_meta',
		
		schema => 
		[
			{	field => 'modelid',	type => 'int(11)',	key => 'PRI', extra=>'auto_increment' },
			{	field => 'timestamp',	type => 'timestamp'	},
			{	field => 'uuid',	type => 'varchar(255)' },
			{	field => 'json',	type => 'longtext'},
		]
	});
	
	sub apply_mysql_schema
	{
		my $self = shift;
		$self->mysql_schema_update(__PACKAGE__);
 	}
};

1;


__DATA__

## File: Drivers.pm

## Call example:
#
# return DriveLink::IntPortal::Drivers->subpage($controller, $req, $r);
#
## Where $controller provides some other business logic functions outside the scope of this example
## and $req is an AppCore::Web::Request object
## and $r   is an AppCore::Web::Result object
##
## Example setup of those objects:
## use AppCore::Web::Request;
## use AppCore::Web::Result;
## my $req = AppCore::Web::Request->new(PATH_INFO => $ENV{PATH_INFO});
## my $r   = AppCore::Web::Result->new();


package DriveLink::IntPortal::Drivers;
{
	use strict;
	use AppCore::Web::Common;
	use base 'AppCore::Web::Controller';
	
	use DriveLink::Driver;
	
	use AppCore::Web::Form;
	use AppCore::Web::SimpleListView;
	use AppCore::DBI::SimpleListModel;
		
	# setup_routes() is called by superclass in dispatch() first time finds no routes setup on this class
	sub setup_routes
	{
		my $class = shift;
		my $router = $class->router;

		$router->route(':driverid/:action'	=> {
			':driverid'	=> {
				regex	=> qr/^\d+$/,
				check	=> sub {
					my ($router, $driverid) = @_;
					my $driver = DriveLink::Driver->retrieve($driverid) || die "Invalid driver ID $driverid\n";
					$router->stash->{driver} = $driver;
					#$router->stash->{driver} = $driverid;
				},
			},
			':action'	=> [
				#[qw/edit post delete/],
				edit		=> 'page_driver_edit',
				post		=> 'page_driver_post',
				delete		=> 'page_driver_delete',
				'/'		=> 'page_driver_view',
			],
		});

		$router->route('/'		=> 'page_driver_list');
		$router->route('new'		=> 'page_driver_new');
		$router->route('new/post'	=> 'page_driver_post_new');
		$router->route('validate'	=> 'AppCore::Web::Form.validate_page');
		
		#die Dumper $router;
	}
	
	sub subpage
	{
		my ($class, $ctrl, $req, $r) = @_;
		
		$class->stash(ctrl => $ctrl);
		$class->dispatch($req, $r);
	}
	
	sub respond
	{
		my $self = shift;
		my $ctrl = $self->stash->{ctrl};
		
		$ctrl->{view}->tmpl_param(intportal_drivers => 1);
		$ctrl->output(@_);
	}
	
	sub page_driver_list
	{
		my ($class) = @_;
		
		my $req = $class->stash->{req};
		
		my $model = AppCore::DBI::SimpleListModel->new('DriveLink::Driver');
		my $view  = AppCore::Web::SimpleListView->new($req, { file => 'tmpl/drivers-list.tmpl' });
		
		# Tell the model to filter by the string given in the request
		$model->set_filter($req->query);
		
		# Add a 'deleted = 0' filter to hide deleted drivers
		$model->set_hardcoded_filter( deleted => 0 );
		
		# We could have set model options after we called set_model(), but is probably safer to do it before to support future expansion.
		# If we were running in a client-side GUI, the model would be ovservable by the view anyway, so it wouldn't matter at all.
		$view->set_model($model);
		
		# Add a small filter to adjust the data from the database before it hits the template
		$view->row_mudge_hook(sub {
			my $row = shift;
			
			$row->{hire_date} = '' if $row->{hire_date} eq '0000-00-00';
			$row->{term_date} = '' if $row->{term_date} eq '0000-00-00';
			$row->{email}     = '' if $row->{email} eq '&nbsp;';
		});
		
		# Setup the view with various view options
		$view->set_paging($req->start || 0, $req->length || 100);
		
		# Add a message to confirm the previous action if present
		my $ac = $req->action_completed;
		if($ac eq 'created' || $ac eq 'updated' || $ac eq 'deleted')
		{
			$view->set_message("Driver # <a href='".$req->page_path.'/'.$req->driverid."'>$req->{driverid}</a> has been $ac.");
		}
		
		return $class->respond($view->output);
	}
	
	sub page_driver_view
	{
		my ($class) = @_;
		
		my $driver = $class->stash->{driver};
		my $ctrl   = $class->stash->{ctrl};
		
		die "Error: No driver in stash" if !$driver;
		
		my $tmpl = $ctrl->get_template('tmpl/drivers-view.tmpl');
		
		# $tmpl is a HTML::Template::DelayedLoading object (defined in AppCore::Web::Common)
		# The param() method, when given an AppCore::DBI-dervied object as the 2nd (value) argument,
		# automatically does the equivelant of:
		#	$tmpl->param($key.'_'.$_ => $val->get($_)) foreach $driver->columns;
		# Where $key is the first argument given to param()
		$tmpl->param('driver' => $driver);
		$tmpl->param('is_avail' => $driver->availability !~ /^out/i);
		$tmpl->param(customer_name => $driver->customerid->name);
		
		return $class->respond($tmpl);
	}
	
	sub page_driver_edit
	{
		my ($class) = @_;
		
		my $driver = $class->stash->{driver};
		my $ctrl   = $class->stash->{ctrl};
		
		die "Error: No driver in stash" if !$driver;
		
		my $tmpl = $ctrl->get_template('tmpl/drivers-edit.tmpl');
		
		$tmpl->param(post_url => $class->url_up(1).'/post');
		$tmpl->param('driver' => $driver);
		
		my $out = AppCore::Web::Form->post_process($tmpl, {
			driver       => $driver,
			validate_url => $class->url_up(2).'/validate',
		});
		
		return $class->respond($out);
	}
		
	sub page_driver_new
	{
		my ($class) = @_;
		
		my $tmpl = $class->stash->{ctrl}->get_template('tmpl/drivers-edit.tmpl');
		
		my $out = AppCore::Web::Form->post_process($tmpl, {
			driver           => 'DriveLink::Driver',
			validate_url     => $class->url_up(1).'/validate',
			allow_undef_bind => 1
		});
		
		return $class->respond($out);
	}
	
	sub page_driver_post_new
	{
		my ($class) = @_;
		
		$class->stash->{driver} = DriveLink::Driver->insert({});
		
		$class->page_driver_post('created');
	}
	
	sub page_driver_post
	{
		my $class  = shift;
		
		my $action = shift || 'updated';
		
		my $driver = $class->stash->{driver};
		my $req    = $class->stash->{req};
		
		die "Error: No driver in stash" if !$driver;
		
		my $tmp = AppCore::Web::Form->store_values($req, { driver => $driver });
		
		# Up 1 just removes 'post' from URL, leaving the /driverid on the URL
		return $class->redirect_up(1);
	}
	
	sub page_driver_delete
	{
		my ($class) = @_;
		
		my $driver = $class->stash->{driver};
		
		die "Error: No driver in stash" if !$driver;
		$driver->deleted(1);
		$driver->update;

		return $class->redirect_up(2, { action_completed => 'deleted', driverid => $driver } );
	}
};


## File drivers-edit.tmpl (partial, just the form)

	<f:form action='%%post_url%%' method='POST' id="edit-form" uuid='DriveLink::Driver'>
		<table class='form-table'>
			<input bind="#driver.customerid" size="61"/><!-- render='select'/>-->
			
			<row label="Name">
				<input bind="#driver.first"/>
				<input bind="#driver.middle" size="7"/>
				<input bind="#driver.last"/>
			</row>
			
			<row label="SSN">
				<row bind="#driver.ssn"/>
				<row bind="#driver.sex"/>
			</row>
			<row label="Birth Date">
				<row bind='#driver.birth_date'/>
				<span id="driver_age_wrapper">
					Age: <span id="driver_age">...</span>
				</span>
				<script>
				//<![CDATA[
				$(function() {
					function recalcAge()
					{
						$("#driver_age_wrapper").hide();
						
						var date = $("#edit-form-driver-birth_date").val();
						if(!date)
							return;
						
						var list = date.split("-");
						if(list.length < 3 || parseInt(list[0]) == 0)
							return;
						
						var d1=new Date(list[0], list[1], list[2]);
						var d2=new Date();

						var milli=d2-d1;
						var milliPerYear=1000*60*60*24*365.26;

						var age = parseInt(milli/milliPerYear);
						
						$("#driver_age_wrapper").show();
						$("#driver_age").html("<b>"+age+"</b> years old");
					}
					$("#edit-form-driver-birth_date").bind('change', recalcAge);
					recalcAge();
				});
				//]]>
				</script>
			</row>
				
			<row bind="#driver.spouse"/>
			<row bind="#driver.dba" label="DBA"/>
			
			<row bind="#driver.comments" rows="5" cols="60"/>
			
			<h2>Contact Info</h2>
			<row bind="#driver.email" size="62"/>
			<row label="Home Phone">
				<row bind="#driver.home_phone" size="12"/>
				<row bind="#driver.cell_phone" label="Cell" size="12"/>
				<row bind="#driver.fax" label="Fax" size="12"/>
			</row>
			<row bind="#driver.address" size="62"/>
			<row label="City">
				<input bind="#driver.city"/>
				<input bind="#driver.state" type="string" datasource="internal.states" length='3'/> <!--choices="AL,IN,MI,SD,TX"/>-->
				<input bind="#driver.zip" size="6"/>
			</row>
			
			<h2>Important Dates</h2>
			<row label="Hire">
				<row bind='#driver.hire_date'/>
				<row bind='#driver.term_date' label="Term"/>
			</row>
			<row bind='#driver.review_date'/>
			<row bind='#driver.physexam_date'/>
			
			<h2>Licence Data</h2>
			<row label="Licence Num">
				<row bind='#driver.licence_num'/>
				<row bind='#driver.licence_expir' label="Expir" size="10"/>
				<row bind='#driver.licence_state' label="State" size="3"/>
			</row>
			<row bind='#driver.passenger_flag'/>
			<row bind='#driver.can_tow'/>
			<row bind='#driver.towins_date'/>
			<row bind='#driver.passport'/>
			<row bind='#driver.twic' label="TWIC"/>
			<row bind='#driver.trans_type'/>
			
			<h2>CDL Information</h2>
			<row label="CDL">
				<!--<input bind='#driver.cdl_class' render='radio'/>-->
				<input bind='#driver.cdl_class'/>
				<input bind='#driver.cdl_ifta_num' label="IFTA#" size="10"/>
			</row>
			
			<row bind='#driver.endorse_tanker'/>
			<row bind='#driver.endorse_dbl'/>
			<row bind='#driver.endorse_tripple'/>
			<row bind='#driver.endorse_combo'/>
			<row bind='#driver.endorse_airbrakes'/>
			<row bind='#driver.endorse_hazmat'/>
			<row bind='#driver.endorse_mocyc'/>
			
			<h2/>

			<tr>
				<td align='right'>
					<a style='color:rgba(0,0,0,0.5)'   href='javascript:void(window.history.go(-1))'>Cancel</a>
				</td>
				<td>
					<tmpl_if driver_driverid>
						<input type='submit' value='Save Changes'/>
						<a style='color:rgba(255,0,0,0.6)' href='%%page_path%%/delete' onclick="return confirm('Are you sure?')">Delete Driver</a>
					<tmpl_else>
						<input type='submit' value='Create Driver'/>
					</tmpl_if>
				</td>
			</tr>
		</table>
	</f:form>

## File: Driver.pm (partial, just for example)

use strict;

package DriveLink::Driver;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta(
	{
		table	=> 'drivers',
		schema  =>
		[
			{ field => 'driverid',		type => 'int',	@AppCore::DBI::PriKeyAttrs },
			{ field => 'customerid',	type => 'int', linked => 'DriveLink::Customer' },
			{ field => 'first',		type => 'varchar(255)' },
			{ field => 'middle',		type => 'varchar(255)' },
			{ field => 'last',		type => 'varchar(255)' },
			{ field => 'display',		type => 'varchar(255)' },
			{ field => 'sex',		type => "enum('Male','Female')", null=>0, default=>'Male' },
			{ field => 'ssn',		type => 'varchar(255)' },
			{ field => 'driver_code',	type => 'varchar(16)' },
			{ field => 'dba',		type => 'varchar(255)' },
			{ field => 'taxid',		type => 'varchar(255)' },
			{ field => 'spouse',		type => 'varchar(255)' },
			{ field => 'email',		type => 'varchar(255)' },
			{ field => 'home_phone',	type => 'varchar(255)' },
			{ field => 'cell_phone',	type => 'varchar(255)' },
			{ field => 'fax',		type => 'varchar(255)' },
			{ field => 'address',		type => 'varchar(255)' },
			{ field => 'city',		type => 'varchar(255)' },
			{ field => 'state',		type => 'varchar(255)' },
			{ field => 'zip',		type => 'varchar(255)' },
			{ field => 'comments',		type => 'text' },
			{ field => 'birth_date',	type => 'date' },
			{ field => 'hire_date',		type => 'date' },
			{ field => 'term_date',		type => 'date' },
			{ field => 'licence_num',	type => 'varchar(255)' },
			{ field => 'licence_expir',	type => 'date' },
			{ field => 'licence_state',	type => 'varchar(5)' },
			{ field => 'physexam_date',	type => 'date' },
			{ field => 'towins_date',	type => 'date' },
			{ field => 'review_date',	type => 'date' },
			{ field => 'passport',		type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'twic',		type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'trans_type',	type => "enum('Auto','Manual')", null=>0, default=>'Auto' },
			{ field => 'cdl_class',		type => "enum('No CDL','A','B','C','CHAUFFER')", null=>0, default=>'No CDL' },
			{ field => 'cdl_ifta_num',	type => 'varchar(255)' },
			{ field => 'passenger_flag',	type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'can_tow',		type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'endorse_tanker',	type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'endorse_dbl',	type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'endorse_tripple',	type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'endorse_combo',	type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'endorse_airbrakes',	type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'endorse_hazmat',	type => "enum('Yes','No')", null=>0, default=>'No' },
			{ field => 'endorse_mocyc',	type => "enum('Yes','No')", null=>0, default=>'No' },
			
			{ field => 'availability',	type => "enum('Out of Service','Available')", null=>0, default=>'Available' }, 
			
			
			{ field => 'deleted',		type => 'int(1)', null => 0, default => 0 },
		],
		
		
		sort => [['last','asc'], ['first','asc']],
	});
};
1;		
