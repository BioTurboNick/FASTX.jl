# FASTQ Record
# ============

mutable struct Record
    # data and filled range
    data::Vector{UInt8}
    filled::UnitRange{Int}
    # indexes
    identifier::UnitRange{Int}
    description::UnitRange{Int}
    sequence::UnitRange{Int}
    quality::UnitRange{Int}
end

"""
    FASTQ.Record()

Create an unfilled FASTQ record.
"""
function Record()
    return Record(UInt8[], 1:0, 1:0, 1:0, 1:0, 1:0)
end

"""
    FASTQ.Record(data::Vector{UInt8})

Create a FASTQ record object from `data`.

This function verifies and indexes fields for accessors.

!!! warning
    Note that the ownership of `data` is transferred to a new record object.
    Editing the input data will edit the record, and is not advised after
    construction of the record.
"""
function Record(data::Vector{UInt8})
    record = Record(data, 1:0, 1:0, 1:0, 1:0, 1:0)
    index!(record)
    return record
end

"""
    FASTQ.Record(str::AbstractString)

Create a FASTQ record object from `str`.

This function verifies and indexes fields for accessors.
"""
function Record(str::AbstractString)
    return Record(Vector{UInt8}(str))
end

Base.parse(::Record, str::AbstractString) = Record(str)

"""
    FASTQ.Record(identifier, sequence, quality; offset=33)

Create a FASTQ record from `identifier`, `sequence` and `quality`.
"""
function Record(identifier::AbstractString, sequence, quality::Vector; offset=33)
    return Record(identifier, nothing, sequence, quality, offset=offset)
end

"""
    FASTQ.Record(identifier, description, sequence, quality; offset=33)

Create a FASTQ record from `identifier`, `description`, `sequence` and `quality`.
"""
function Record(identifier::AbstractString, description::Union{AbstractString,Nothing}, sequence, quality::Vector; offset=33)
    if length(sequence) != length(quality)
        throw(ArgumentError("the length of sequence doesn't match the length of quality"))
    end
    buf = IOBuffer()
    print(buf, '@', identifier)
    if description != nothing
        print(buf, ' ', description)
    end
    print(buf, '\n')
    print(buf, sequence, '\n')
    print(buf, "+\n")
    ascii_quality = convert(Vector{UInt8}, quality .+ offset)
    write(buf, ascii_quality, '\n')
    return Record(take!(buf))
end

function Base.:(==)(record1::Record, record2::Record)
    if isfilled(record1) == isfilled(record2) == true
        r1 = record1.filled
        r2 = record2.filled
        return length(r1) == length(r2) && memcmp(pointer(record1.data, first(r1)), pointer(record2.data, first(r2)), length(r1)) == 0
    else
        return isfilled(record1) == isfilled(record2) == false
    end
end

function Base.copy(record::Record)
    return Record(
        record.data[record.filled],
        record.filled,
        record.identifier,
        record.description,
        record.sequence,
        record.quality)
end

function Base.write(io::IO, record::Record)
    return unsafe_write(io, pointer(record.data, first(record.filled)), length(record.filled))
end

function Base.print(io::IO, record::Record)
    write(io, record)
    return nothing
end

function Base.show(io::IO, record::Record)
    print(io, summary(record), ':')
    if isfilled(record)
        println(io)
        println(io, "   identifier: ", hasidentifier(record) ? identifier(record) : "<missing>")
        println(io, "  description: ", hasdescription(record) ? description(record) : "<missing>")
        println(io, "     sequence: ", hassequence(record) ? sequence(String, record) : "<missing>")
          print(io, "      quality: ", hasquality(record) ? quality(record) : "<missing>")
    else
        print(io, " <not filled>")
    end
end

function initialize!(record::Record)
    record.filled = 1:0
    record.identifier = 1:0
    record.description = 1:0
    record.sequence = 1:0
    record.quality = 1:0
    return record
end

function BioGenerics.isfilled(record::Record)
    return !isempty(record.filled)
end

function memcmp(p1::Ptr, p2::Ptr, n::Integer)
    return ccall(:memcmp, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t), p1, p2, n)
end


# Accessor functions
# ------------------

"""
    identifier(record::Record)::Union{String,Nothing}

Get the sequence identifier of `record`.

!!! note
    Returns `nothing` if the record has no identifier.
"""
function identifier(record::Record)::Union{String,Nothing}
    checkfilled(record)
    if !hasidentifier(record)
        return nothing
    end
    return String(record.data[record.identifier])
end

"""
    hasidentifier(record::Record)

Checks whether or not the `record` has an identifier.
"""
function hasidentifier(record::Record)
    return isfilled(record)
end


"""
    description(record::Record)::Union{String, Nothing}

Get the description of `record`.

!!! note
    Returns `nothing` if `record` has no description.
"""
function description(record::Record)::Union{String, Nothing}
    checkfilled(record)
    if !hasdescription(record)
        nothing
    end
    return String(record.data[record.description])
end

"""
    hasdescription(record::Record)

Checks whether or not the `record` has a description.
"""
function hasdescription(record)
    return isfilled(record) && record.description != 1:0
end

function Base.copy!(dest::BioSequences.LongSequence, src::Record)
    resize!(dest, seqlen(src) % UInt)
    copyto!(dest, 1, src, 1, seqlen(src))
end

"""
    header(record::Record)::Union{String, Nothing}

Returns the stripped header line of `record`, or `nothing` if it was empty.
"""
function header(record::Record)
    hasidentifier(record) || return nothing
    id, desc = record.identifier, record.description
    range = first(id) : max(last(id), last(desc))
    return String(record.data[range])
end

"""
    Base.copyto!(dest::BioSequences.LongSequence, src::Record)

Copy all of the sequence data from the fastq record `src` to a biological
sequence `dest`. `dest` must have a length greater or equal to the length of
the sequence represented in the fastq record. The first n elements of `dest` are
overwritten, the other elements are left untouched.
"""
function Base.copyto!(dest::BioSequences.LongSequence, src::Record)
    return copyto!(dest, 1, src, 1, seqlen(src))
end

"""
    Base.copyto!(dest::BioSequences.LongSequence, doff, src::Record, soff, N)

Copy an N long block of sequence data from the fastq record `src`, starting at
position `soff`, to the `BioSequence` dest, starting at position `doff`.
"""
function Base.copyto!(dest::BioSequences.LongSequence, doff, src::Record, soff, N)
    checkfilled(src)
    if !hassequence(src)
        missingerror(:sequence)
    end
    return copyto!(dest, doff, src.data, src.sequence[soff], N)
end

"""
    sequence_iter(T, record::Record)

Yields an iterator of the sequence, with elements of type `T`. `T` is constructed
through `T(Char(x))` for each byte `x`. E.g. `sequence_iter(DNA, record)`.
Mutating the record will corrupt the iterator.
"""
function sequence_iter(::Type{T}, record::Record,
    part::UnitRange{<:Integer}=1:lastindex(record.sequence)) where {T <: BioSymbols.BioSymbol}
    checkfilled(record)
    seqpart = record.sequence[part]
    data = record.data
    return (T(Char(@inbounds (data[i]))) for i in seqpart)
end

"""
    sequence(::Type{S}, record::Record, [part::UnitRange{Int}])

Get the sequence of `record`.

`S` can be either a subtype of `BioSequences.LongSequence` or `String`.
If `part` argument is given, it returns the specified part of the sequence.

!!! note
    This method makes a new sequence object every time.
    If you have a sequence already and want to fill it with the sequence
    data contained in a fastq record, you can use `Base.copyto!`.
"""
function sequence(::Type{S}, record::Record, part::UnitRange{Int}=1:lastindex(record.sequence))::S where S <: BioSequences.LongSequence
    checkfilled(record)
    seqpart = record.sequence[part]
    return S(record.data, first(seqpart), last(seqpart))
end

"""
    sequence(::Type{String}, record::Record, [part::UnitRange{Int}])::String

Get the sequence of `record` as a String.
If `part` argument is given, it returns the specified part of the sequence.
"""
function sequence(::Type{String}, record::Record, part::UnitRange{Int}=1:lastindex(record.sequence))::String
    checkfilled(record)
    return String(record.data[record.sequence[part]])
end

"""
    sequence(record::Record, [part::UnitRange{Int}])::BioSequences.DNASequence

Get the sequence of `record`.

!!! note
    This method makes a new sequence object every time.
    If you have a sequence already and want to fill it with the sequence
    data contained in a fastq record, you can use `Base.copyto!`.
"""
function sequence(record::Record, part::UnitRange{Int}=1:lastindex(record.sequence))::BioSequences.LongDNASeq
    return sequence(BioSequences.LongDNASeq, record, part)
end

"""
    hassequence(record::Record)

Checks whether or not a sequence record contains a sequence.

!!! note
    Zero-length sequences are allowed in records.
"""
function hassequence(record::Record)
    # zero-length sequence may exist
    return isfilled(record)
end

"Get the length of the fastq record's sequence."
@inline seqlen(record::Record) = last(record.sequence) - first(record.sequence) + 1

"""
    quality_iter(record::Record, [offset::Integer=33, [part::UnitRange]])::Vector{UInt8}

Get an iterator of base quality of `record`. This iterator is corrupted if the record is mutated.
"""
function quality_iter(record::Record, offset::Integer=33, part::UnitRange{Int}=1:lastindex(record.quality))
    checkfilled(record)
    offs = convert(UInt8, offset)
    part = record.quality[part]
    data = record.data
    return (@inbounds(data[i]) - offs for i in part)
end

"""
    quality(record::Record, [offset::Integer=33, [part::UnitRange]])::Vector{UInt8}

Get the base quality of `record`.
"""
function quality(record::Record, offset::Integer=33, part::UnitRange{Int}=1:lastindex(record.quality))::Vector{UInt8}
    collect(quality_iter(record, offset, part))
end
"""
    quality(record::Record, encoding_name::Symbol, [part::UnitRange])::Vector{UInt8}

Get the base quality of `record` by decoding with `encoding_name`.

The `encoding_name` can be either `:sanger`, `:solexa`, `:illumina13`, `:illumina15`, or `:illumina18`.

!!! note
    Returns `nothing` if the record has no quality string.
"""
function quality(record::Record, encoding_name::Symbol, part::UnitRange{Int}=1:lastindex(record.quality))::Vector{UInt8}
    checkfilled(record)
    encoding = (
        encoding_name == :sanger     ?     SANGER_QUAL_ENCODING :
        encoding_name == :solexa     ?     SOLEXA_QUAL_ENCODING :
        encoding_name == :illumina13 ? ILLUMINA13_QUAL_ENCODING :
        encoding_name == :illumina15 ? ILLUMINA15_QUAL_ENCODING :
        encoding_name == :illumina18 ? ILLUMINA18_QUAL_ENCODING :
        throw(ArgumentError("quality encoding ':$(encoding_name)' is not supported")))
    quality = Vector{UInt8}(undef, length(part))
    if !isempty(part)
        qpart = record.quality[part]
        check_quality_string(encoding, record.data, first(qpart), last(qpart))
        decode_quality_string!(encoding, record.data, quality, first(qpart), last(qpart))
    end
    return quality
end

"""
    hasquality(record::Record)

Check whether the given FASTQ `record` has a quality string.
"""
function hasquality(record::Record)
    return isfilled(record)
end

function BioGenerics.seqname(record::Record)
    return identifier(record)
end

function BioGenerics.hasseqname(record::Record)
    return hasidentifier(record)
end

function BioGenerics.sequence(record::Record)
    return sequence(record)
end

function BioGenerics.sequence(::Type{S}, record::Record) where S <: BioSequences.LongSequence
    return sequence(S, record)
end

function BioGenerics.hassequence(record::Record)
    return hassequence(record)
end

function Base.hash(record::Record, h::UInt)
    return hash(identifier(record), hash(description(record), hash(sequence(record),
                hash(quality(record), h))))
end


# Helper functions
# ----------------

function checkfilled(record)
    if !isfilled(record)
        throw(ArgumentError("unfilled FASTQ record"))
    end
end
