package Kwiki::Purple::Sequence;
use Kwiki::Plugin '-Base';
use Kwiki::Installer '-base';

const class_id             => 'purple_sequence';
const class_title          => 'Purple Sequence';
const css_file             => 'purple.css';
const config_file          => 'purple_sequence.yaml';

our $VERSION = '0.01';

sub lock_directory {
    $self->sequence_file . '.lck';
}

sub sequence_file {
    $self->config->purple_sequence_file
      ? $self->config->purple_sequence_file
      : $self->plugin_directory . '/' . 'sequence';
}

# taken from PurpleWiki
sub lock {
    my $tries = 0;
    while (mkdir($self->lock_directory, 0555) == 0) {
        die "unable to create sequence locking directory"
          if ($! != 17);
        $tries++;
        die "timeout attempting to lock sequence"
          if ($tries > $self->config->purple_sequence_lock_count);
        sleep 1;
    }
}

sub unlock {
    rmdir($self->lock_directory) or
      die "unable to remove sequence locking directory";
}

# XXX eventually there will be an index
# of NID to URL or NID to page information
# For the time being one Kwiki only talks to itself
sub update_index {
}

sub get_next {
    my $page = shift;
    $self->lock;
    my $nid = $self->update_value($self->increment_value($self->get_value));
    $self->update_index($page, $nid);
    $self->unlock;
    return $nid;
}

sub get_value {
    io($self->sequence_file)->print(0) unless io($self->sequence_file)->exists;
    io($self->sequence_file)->all;
}

sub update_value {
    my $value = shift;
    io($self->sequence_file)->print($value);
    return $value;
}

# XXX taken right out of purplewiki, i'm quite sure this can
# be made more smarter. might make sense to just go with ints
sub increment_value {
    my $value = shift;
    $value ||= 0;

    my @oldValues = split('', $value);
    my @newValues;
    my $carryBit = 1;

    foreach my $char (reverse(@oldValues)) {
        if ($carryBit) {
            my $newChar;
            ($newChar, $carryBit) = $self->inc_char($char);
            push(@newValues, $newChar);
        } else {
            push(@newValues, $char);
        }
    }
    push(@newValues, '1') if ($carryBit);
    return join('', (reverse(@newValues)));
}

sub inc_char {
    my $char = shift;

    if ($char eq 'Z') {
        return '0', 1;
    }
    if ($char eq '9') {
        return 'A', 0;
    }
    if ($char =~ /[A-Z0-9]/) {
        return chr(ord($char) + 1), 0;
    }
}


package Kwiki::Purple::Sequence;

__DATA__

=head1 NAME

Kwiki::Purple::Sequence - Provide the next purple number and store it

=head1 DESCRIPTION

A Kwiki::Purple::Sequence is a source of the next Purple Number used
for creating nids in L<Kwiki::Purple> to ensure that no nid is used
more than once. That's all this version does at this time.

A fully implemented Sequence maintains an index of NID:PageName or
NID:URL pairs to allow for transclusion amongst multiple wikis or
other sources of nid identified information.

Based in very large part on PurpleWiki::Sequence, which has more
functionality.

=head1 AUTHORS

Chris Dent, <cdent@burningchrome.com>

=head1 SEE ALSO

L<Kwiki::Purple>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005, Chris Dent

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
__config/purple_sequence.yaml__
purple_sequence_file:
purple_sequence_lock_count: 10
