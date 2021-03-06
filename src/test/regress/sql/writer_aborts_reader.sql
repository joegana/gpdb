-- Tests to validate that in a multi-slice query a QE writer signals QE readers
-- to cancel query execution before marking the transaction as aborted.
-- The tests make use of a "skip" fault to determine if the control reached a
-- specific location of interest.  In this case, the location of the fault
-- "cancelled_reader_during_abort" is right after a writer sends SIGINT to
-- corresponding readers.

CREATE EXTENSION IF NOT EXISTS gp_inject_fault;
create table writer_aborts_before_reader_a(i int, j int) distributed by (i);
alter table writer_aborts_before_reader_a add constraint check_j check (j > 0);
insert into writer_aborts_before_reader_a select 4,i from generate_series(1,12) i;

create table writer_aborts_before_reader_b (like writer_aborts_before_reader_a) distributed by (i);
insert into writer_aborts_before_reader_b select * from writer_aborts_before_reader_a;

-- first test: one writer with one or more readers
select gp_inject_fault('cancelled_reader_during_abort', 'skip', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

begin;
-- Make a write in this transaction so that a TransactionId will be assigned.
insert into writer_aborts_before_reader_a values (4, 4);
-- This multi-slice update is aborted because QE writer encounters constraint
-- failure.  The writer must send cancel signal to the readers before aborting the
-- transaction.  The fault, therefore, is expected to hit at least once.
update writer_aborts_before_reader_a set j = -1 from writer_aborts_before_reader_b;
end;

select gp_wait_until_triggered_fault('cancelled_reader_during_abort', 1, dbid) from
gp_segment_configuration where role = 'p' and content = 0;

select gp_inject_fault('cancelled_reader_during_abort', 'reset', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

-- second test: one writer with no readers
select gp_inject_fault('cancelled_reader_during_abort', 'skip', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

begin;
-- Make a write in this transaction so that a TransactionId will be assigned.
insert into writer_aborts_before_reader_a values (4, 4);
-- No reader gangs. This is a single slice update.  The writer aborts the
-- transaction because of constraint failure.
update writer_aborts_before_reader_a set j = -1;
end;

-- The writer from the previous update statement is not expceted to walk the
-- proc array and look for readers because that was a single-slice statement.
-- Therefore, hit count for the fault should be 0.
select gp_inject_fault('cancelled_reader_during_abort', 'status', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

select gp_inject_fault('cancelled_reader_during_abort', 'reset', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

-- third test: writer and reader, but the transaction does not write
select gp_inject_fault('cancelled_reader_during_abort', 'skip', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

begin;
-- This is a non-colocated join, with two slices.
select count(*) from writer_aborts_before_reader_a, writer_aborts_before_reader_b
where writer_aborts_before_reader_a.i = writer_aborts_before_reader_b.j;
abort;

-- The previous abort should cause the QE writer to go through abort workflow.
-- But the writer should not walk the proc array and look for readers because the
-- transaction did not make any writes.  Therefore, the fault status is expected
-- to return hit count as 0.
select gp_inject_fault('cancelled_reader_during_abort', 'status', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

select gp_inject_fault('cancelled_reader_during_abort', 'reset', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

-- fourth test: the transaction does write but the last command before
-- abort is read-only
select gp_inject_fault('cancelled_reader_during_abort', 'skip', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

begin;
-- Make a write in this transaction so that a TransactionId will be assigned.
insert into writer_aborts_before_reader_a values (4, 4);
-- Both the slices in this query plan have gangType PRIMARY_READER
select count(*) from writer_aborts_before_reader_a, writer_aborts_before_reader_b
where writer_aborts_before_reader_a.i = writer_aborts_before_reader_b.j;
abort;

-- QE writer should not walk through proc array during abort to look
-- for readers because none of the slices in the last command had
-- gangType PRIMARY_WRITER.  Hit count reported by the status should
-- therefore be 0.
select gp_inject_fault('cancelled_reader_during_abort', 'status', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

select gp_inject_fault('cancelled_reader_during_abort', 'reset', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

-- fifth test: a multi-slice query is aborted in a subtransaction
select gp_inject_fault('cancelled_reader_during_abort', 'skip', dbid) from
gp_segment_configuration where role = 'p' and content = 0;

begin;
-- Make a write in this transaction so that a TransactionId will be
-- assigned to the top transaction.
insert into writer_aborts_before_reader_a values (4, 4);
savepoint sp1;
-- Make a write so that a TransactionId will be assigned to this
-- subtranaction.
insert into writer_aborts_before_reader_a values (4, 4);
-- The QE writer should hit an error and walk through proc array to
-- signal all readers before marking the transaction aborted.
update writer_aborts_before_reader_a set j = -1 from writer_aborts_before_reader_b;
rollback to sp1;
-- The top transaction should remain in-progress, even after the
-- readers were signaled to cancel.  Verify that by executing a query.
select count(*) from writer_aborts_before_reader_a, writer_aborts_before_reader_b
where writer_aborts_before_reader_a.i = writer_aborts_before_reader_b.j;
commit;

-- The fault should be hit during subtransaction abort because the
-- writer should wait for readers before marking the subtransaction as
-- aborted.
select gp_inject_fault('cancelled_reader_during_abort', 'status', dbid) from
gp_segment_configuration where role = 'p' and content = 0;
select gp_inject_fault('cancelled_reader_during_abort', 'reset', dbid) from
gp_segment_configuration where role = 'p' and content = 0;
