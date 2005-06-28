package Kwiki::Purple;
use Kwiki::Plugin '-Base';
use Kwiki::Installer '-base';

const class_id             => 'purple';
const class_title          => 'Purple';
const css_file             => 'purple.css';
const hook_classes         => [qw(heading p li td)];
const cgi_class            => 'Kwiki::Purple::CGI';

field hooked => 0;

# XXX some of these don't work, such a titlehyper
 my %formatter_text_flags = (
     tr          => ['|', "\n"],
     td          => ['', '|'],
     hr          => ['----', "\n\n"],
);
# actually, we don't want to to_text on the Phrases, just the blocks
#my %formatter_text_flags = ();

our $VERSION = '0.03';

sub init {
    super;
    return unless $self->is_in_cgi;
    $self->establish_formatter_overrides;
}

sub register {
    my $registry = shift;
    $registry->add(hook => 'page:store', pre => 'update_nids');
    $registry->add(wafl => nid => 'Kwiki::Purple::Nid::Wafl');
    $registry->add(wafl => t => 'Kwiki::Purple::Transclusion::Wafl');
    $registry->add(action => 'get_node');
    $registry->add(prerequisite => 'purple_sequence');
}

sub establish_formatter_overrides {
    $self->start_nid;
    $self->invade_formatter;
}

sub invade_formatter {
    my $formatter = $self->hub->formatter;
    my $table = $formatter->table;
    $table->{li} = 'Kwiki::Formatter::Purple::Item';
    $table->{heading} = 'Kwiki::Formatter::Purple::Heading';
    $table->{wiki} = 'Kwiki::Formatter::Purple::WikiLink';
    no strict 'refs';
    no warnings 'redefine'; # XXX for sake of tests
    foreach my $key (keys(%formatter_text_flags)) {
        my $class = $table->{$key};
        my $ts = 'text_start';
        my $te = 'text_end';
        my $start = "$class\::$ts";
        my $end = "$class\::$te";
        my $info = $formatter_text_flags{$key};
        my $open = $info->[0];
        my $close = $info->[1];
        $open ||= '';
        $close ||= '';
        *{"$start"} = sub {$open};
        *{"$end"} = sub {$close};
    }
}

sub Spoon::Formatter::Unit::to_text {
    my $self = shift;
    $self->get_text;
}

sub Spoon::Formatter::Unit::get_text {
    my $self = shift;
    my $inner;
    if (@{$self->units}) {
        $inner = join '', map {
            ref($_)
              ? $_->to_text
                ? $_->to_text
                : $_->matched
              : $_;
        } @{$self->units};
    } else {
        $inner = $self->matched;
    }
    $self->text_start . $inner . $self->text_end;
}

# XXX should be a way to determine these rather than beat on it like this
sub Spoon::Formatter::Unit::text_start {''}
sub Spoon::Formatter::Unit::text_end {''}
sub Spoon::Formatter::Block::text_end {"\n\n"}
sub Spoon::Formatter::WaflBlock::text_start {'.' . shift->method . "\n"}
sub Spoon::Formatter::WaflBlock::text_end {'.' . shift->method . "\n"}


# XXX presumably much or all of this can be moved into 
# the ::Formatter::Purple:: classes? 
sub start_nid {
    my $formatter = $self->hub->formatter;
    my $table = $formatter->table;
    my $start = 'html_start';
    my $end = 'html_end';
    no strict 'refs';
    no warnings 'redefine';
    for my $type (@{$self->hook_classes}) {
        my $class = $table->{$type};
        my $start = "$class\::$start";
        my $end = "$class\::$end";
        *{"$start"} = 
         sub {
             my $self = shift;
             my $nid = $self->units->[-1];
             my $level = '';
             my $element = $type;
             if ($type eq 'heading') {
                 $level = $self->level;
                 $element = 'h';
             }
             my $nid_value =
               (ref($nid) and $nid->isa('Kwiki::Purple::Nid::Wafl'))
               ? ' id="nid' . $nid->nid . '"'
               : '';
             qq(<${element}${level}${nid_value}>);
         };
    }
}

sub update_nids {
    my $hook = pop;
    my $page = $self;
    $self = $self->hub->purple;
    $self->update($page);
}

sub update {
    my $page = shift;
    my $formatter = $self->hub->formatter;
    my %hooks;
    unless ($self->hooked) {
        $self->hooked(1);
        my $table = $formatter->table;
        for my $class (@$table{@{$self->hook_classes}}) {
            $hooks{$class} = $self->hub->add_hook(
                $class . '::unit_match', post => 'purple:check_nid'
            );
        }
    }
    my $units = $self->hub->formatter->text_to_parsed($page->content);
    $page->content($units->to_text);
    for my $class (keys(%hooks)) {
        $hooks{$class}->unhook;
    }
}

sub check_nid {
    my $hook = pop;
    my $unit = $self;
    $self = $self->hub->purple;
    my $text = $unit->text;
    my ($nid) = ($text =~ /{nid ([A-Z0-9]+)}\s*/);
    unless ($nid) {
        $nid = $self->next_nid;
        $text =~ s/(?: |=)*(\n{0,2})\n*$/ {nid $nid}$1/;
        $unit->text($text);
    }
    $self->write_node($nid, $unit->text);
}

sub write_node {
    # we just went to the trouble of adding the nid, but let's
    # go ahead and removeit before storing
    my $nid = shift;
    my $text = shift;
    my $page_id = $self->hub->pages->current->id;
    $text =~ s/\s*{nid [A-Z0-9]+}\s*$//;
    io($self->plugin_directory . '/' . $nid)->print($text);
    io($self->plugin_directory . '/' . $nid . '.name')->print($page_id);
}

sub get_node {
    my $nid = $self->cgi->nid;
    my $format = $self->cgi->format || 'raw';
    $self->retrieve_node($nid, $format);
}
sub retrieve_node {
    my $nid = shift;
    my $format = shift;
    my $method = 'retrieve_node_' . $format;
    $self->$method($nid);
}

sub retrieve_node_raw {
    my $nid = shift;
    $self->hub->headers->content_type('text/plain');
    $self->read_node($nid);
}

# Track recursion loops, at least in this process...
my $semaphore = [];

sub retrieve_node_html {
    my $nid = shift;
    my $text = $self->read_node($nid);
    my $name = $self->read_node_name($nid);
    my $script = $self->hub->config->script_name;

    # XXX Loop detection needs to be more effective
    unless ((grep {$nid} @$semaphore)) {
        push @$semaphore, $nid;
        my $unit = Spoon::Formatter::Block->new;
        $unit->text($text);
        my $html = $unit->parse->to_html;
        $semaphore = [];
        return qq(<span class="transclusion">$html) .
          qq(&nbsp;<a class="nid" href="$script?$name#nid$nid">T</a></span>);
    } else {
        return qq(<a class="transclusion_loop" href="$script?$name#nid$nid">) .
          qq(TLE</a>);
    }
}

sub read_node {
    my $nid = shift;
    my $file = io($self->plugin_directory . '/' . $nid);
    $file->exists 
      ? $file->all
      : '';
}

sub read_node_name {
    my $nid = shift;
    my $file = io($self->plugin_directory . '/' . $nid . '.name');
    $file->exists
      ? $file->all
      : '';
}

sub next_nid {
    $self->hub->purple_sequence->get_next;
}

##########################################################################
package Kwiki::Purple::CGI;
use Kwiki::CGI -base;

cgi 'nid';
cgi 'format';

##########################################################################
package Kwiki::Purple::Nid::Wafl;
use Spoon::Formatter;
use base 'Spoon::Formatter::WaflPhrase';
const formatter_id => 'nid_wafl';

sub nid {
    my $value = shift;
    $self->{nid} = $value if $value;
    return $self->{nid};
}

sub parse_phrases {
    my ($nid, @else) = split(' ', $self->arguments);
    $self->nid($nid) if ($nid and not @else);
    super;
}
 
sub to_html { 
    qq(&nbsp;<a class="nid" href="#nid) .
       $self->nid . qq(">) . $self->nid .  '</a>';
}

sub text {''}

sub to_text {
    '{nid ' . $self->nid . '}';
}


######################################################################
package Kwiki::Formatter::Purple::WikiLink;
use Kwiki::Formatter;
use base 'Kwiki::Formatter::WikiLink';
use Kwiki ':char_classes';
our $pattern =
  qr/[$UPPER](?=[$WORD]*[$UPPER])(?=[$WORD]*[$LOWER])[$WORD]+(?:\#[0-9A-Z]+){0,1}/;
const pattern_start => qr/$pattern|!$pattern/;

sub html {
    my $page_name = $self->escape_html($self->matched);
    return $page_name
      if $page_name =~ s/^!//;
    my $nid;
    ($page_name, $nid) = split('#', $page_name);
    # XXX hack!
    my $link = $self->hub->pages->new_from_name($page_name)->kwiki_link;
    if ($nid) {
        $link =~ s/$page_name"/$page_name#nid$nid"/;
        $link =~ s{(\w+)(<\/a>)}{$1#$nid$2};
    }
    return $link;
}


######################################################################
package Kwiki::Formatter::Purple::Heading;
use Kwiki::Formatter;
use base 'Kwiki::Formatter::Heading';

sub text_start {
    return '=' x $self->level . ' ';
}


######################################################################
package Kwiki::Formatter::Purple::Item;
use Kwiki::Formatter;
use base 'Kwiki::Formatter::Item';

field buttons => '';

sub text_start { $self->buttons }
sub text_end { "\n" }

sub match {
    my $bullet = $self->bullet;
    return unless 
      $self->text =~ /^($bullet)(.*)\n/m;
    $self->buttons($1);
    $self->set_match($2);
}

##########################################################################
package Kwiki::Purple::Transclusion::Wafl;
use Spoon::Formatter;
use base 'Spoon::Formatter::WaflPhrase';

# XXX this has some issues with looping
sub to_html {
    my ($nid, @else) = split(' ', $self->arguments);
    return $self->wafl_error unless ($nid and not @else);
    $self->hub->purple->retrieve_node_html($nid);
}

package Kwiki::Purple;

__DATA__

=head1 NAME

Kwiki::Purple - Support Purple Numbers in Kwiki

=head1 DESCRIPTION

Kwiki::Purple adds support for granular addressability and transclusion
of content in Kwiki pages, based (somewhat loosely) on the PurpleWiki model.

When this plugin is installed and a page is saved, each heading, paragraph
or list item has a nid appended to its saved text. That looks like this:

   Some text in a paragraph {nid 1}

When the page is formatted to html, this nid will be presented as
a clickable anchor pointing directly to the identified paragraph.

When editing the paragraph, do not remove the {nid} wafl unless
you remove the paragraph outright. If you are just making an edit, 
leave the nid in place. Doing so allows continued granular access
to the chunk of text identified by the nid.

Any section of text which is identified by a nid may be transcluded
elsewhere in the wiki. Transclusion is a sort of reuse by reference
rather than copy. Transclusion has its own wafl:

  This will transclude nid 1 {t 1} into this paragraph

When formatted the output will look similar to:

  This will transclude nid 1 Some text in a paragraph into this paragraph

Some care it taken to prevent loops. 

With experience, this system can become very handy for reusing
or pointing to information that you store in your wiki. 

For more information on Purple Numbers see L<http://purple.blueoxen.net/>,
L<http://purplewiki.blueoxen.net/> and L<http://www.burningchrome.com/~cdent/mt/archives/cat_purple.html>.

=head1 AUTHORS

Chris Dent, <cdent@burningchrome.com>

Many thanks to Brian Ingerson, Matthew O'Connor and Eugene Eric Kim
for various bits of help and inspiration.

=head1 SEE ALSO

L<Kwiki>
L<Spoon::Hooks>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005, Chris Dent

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
__css/purple.css__
a.nid {
    font-family: Verdana, Trebuchet, Arial, Helvetica;
    font-style: normal;
    font-weight: bold;
    font-size: x-small;
    text-decoration: none;
    color: #C8A8FF;  /* light purple */
}

.transclusion {
    border-bottom: thin solid #c8a8FF;
} 

.transclusion_loop {
    font-family: Verdana, Trebuchet, Arial, Helvetica;
    font-style: normal;
    font-weight: bold;
    font-size: x-small;
    text-decoration: none;
    color: #ff08c8;
}

body {
    padding-bottom: 25em;
}
