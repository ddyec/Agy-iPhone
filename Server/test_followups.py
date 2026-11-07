import io
import json
import os
import subprocess
import sys
from pathlib import Path
import socket
import tempfile
import threading
import time
import unittest
import uuid

from gateway import Gateway, Failure
from test_gateway import FAKE


class FollowupTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name).resolve()
        binary=self.root/'agy'; binary.write_text(FAKE); binary.chmod(0o700)
        self.g=Gateway(self.root/'state','k'*48,str(binary),[self.root])
        self.s=self.g.create({})
        self.captures=[]
        def capture(sid,prompt):
            self.captures.append((sid,prompt))
        self.g.run=capture

    def tearDown(self):
        self.g.active.clear()
        self.g.db.close(); self.temp.cleanup()

    def body(self, text, delivery='queue'):
        return {'text':text,'delivery':delivery,'requestID':str(uuid.uuid4())}

    def running(self):
        self.g.submit(self.s['id'],{'text':'first','requestID':str(uuid.uuid4())})

    def finish(self, success=True):
        sid=self.s['id']
        with self.g.lock:
            s=self.g.get(sid); s['running']=False; s['error']='' if success else '任务已停止'; self.g.save(s)
            self.g.active.discard(sid)
            self.g.followups.finished(sid,success)

    def test_fifo_survives_updates_and_same_id_is_idempotent(self):
        self.running(); a=self.body('second'); b=self.body('third')
        self.g.submit(self.s['id'],a); self.g.submit(self.s['id'],b); self.g.submit(self.s['id'],a)
        self.assertEqual([v['text'] for v in self.g.get(self.s['id'])['inbox']],['second','third'])
        self.assertEqual(len(self.g.get(self.s['id'])['messages']),2)
        with self.assertRaises(Failure): self.g.submit(self.s['id'],{**a,'text':'changed'})
        self.finish()
        self.assertEqual(self.g.get(self.s['id'])['messages'][-2]['text'],'second')
        self.finish()
        self.assertEqual(self.g.get(self.s['id'])['messages'][-2]['text'],'third')

    def test_stop_holds_queue_and_resume_is_explicit(self):
        self.running(); body=self.body('later'); self.g.submit(self.s['id'],body)
        self.finish(False)
        item=self.g.get(self.s['id'])['inbox'][0]
        self.assertEqual(item['status'],'held')
        self.g.followups.change(self.s['id'],body['requestID'],'resume')
        self.assertEqual(self.g.get(self.s['id'])['messages'][-2]['text'],'later')

    def test_cancel_and_cross_session_isolation(self):
        self.running(); body=self.body('later'); self.g.submit(self.s['id'],body)
        other=self.g.create({})
        with self.assertRaises(Failure): self.g.followups.change(other['id'],body['requestID'],'cancel')
        self.g.followups.change(self.s['id'],body['requestID'],'cancel')
        self.finish()
        self.assertEqual(len(self.g.get(self.s['id'])['messages']),2)

    def test_guidance_is_claimed_once_without_stopping_current_turn(self):
        self.g.review=object()  # Model the enabled hook capability; no tool approval is granted.
        self.running(); body=self.body('change direction','steer'); self.g.submit(self.s['id'],body)
        before=self.g.get(self.s['id'])['messages'][-1]['id']
        injected=self.g.followups.claim(self.s['id'])
        self.assertEqual(injected,[{'userMessage':'change direction'}])
        self.assertEqual(self.g.followups.claim(self.s['id']),[])
        after=self.g.get(self.s['id'])
        self.assertTrue(after['running']); self.assertEqual(after['messages'][-1]['id'],before)
        self.assertEqual(after['messages'][-1]['guidance'][0]['id'],body['requestID'])
        self.assertEqual(after['inbox'][0]['status'],'delivered')
        with self.assertRaises(Failure): self.g.followups.change(self.s['id'],body['requestID'],'cancel')
        self.g.review=None

    def test_restart_holds_pending_and_never_replays(self):
        self.running(); body=self.body('later'); self.g.submit(self.s['id'],body)
        reopened=Gateway(self.root/'state','k'*48,self.g.binary,[self.root])
        try:
            self.assertEqual(reopened.get(self.s['id'])['inbox'][0]['status'],'held')
            self.assertFalse(reopened.active)
        finally: reopened.db.close()

    def test_references_validated_before_queue_and_again_before_execution(self):
        self.running(); f=self.root/'中文.txt'; f.write_text('data')
        body=self.body('read'); body['references']=[str(f)]
        self.g.submit(self.s['id'],body)
        f.unlink(); self.finish()
        self.assertEqual(self.g.get(self.s['id'])['inbox'][0]['status'],'held')
        with self.assertRaises(Failure): self.g.submit(self.s['id'],{**self.body('bad'),'references':['/etc/passwd']})

    def test_invocation_hook_emits_user_steps_and_only_then_forces_continuation(self):
        from approvals import ApprovalBridge
        bridge=ApprovalBridge(self.root/'invoke.sock',lambda sid, records:None,guidance=self.g.followups.claim)
        self.g.review=bridge
        self.running(); body=self.body('follow this correction','steer'); self.g.submit(self.s['id'],body)
        token=bridge.begin(self.s['id'])
        env=dict(os.environ,AGY_IPHONE_REVIEW_SOCKET=bridge.path,AGY_IPHONE_RUN_TOKEN=token)
        hook=Path(__file__).with_name('steering_hook.py')
        try:
            result=subprocess.run([sys.executable,str(hook),'--after'],input=b'{}',capture_output=True,env=env,timeout=10,check=True)
            self.assertEqual(json.loads(result.stdout),{'injectSteps':[{'userMessage':'follow this correction'}],'terminationBehavior':'force_continue'})
            again=subprocess.run([sys.executable,str(hook),'--after'],input=b'{}',capture_output=True,env=env,timeout=10,check=True)
            self.assertEqual(json.loads(again.stdout),{})
            self.assertEqual(len(self.g.get(self.s['id'])['messages']),2)
        finally:
            bridge.finish(token); bridge.close(); self.g.review=None

    def test_steering_socket_does_not_bypass_permission_or_other_tokens(self):
        from approvals import ApprovalBridge
        bridge=ApprovalBridge(self.root/'hook.sock',lambda sid, records:None,guidance=lambda sid:[{'userMessage':'for '+sid}])
        def ask(token):
            with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as sock:
                sock.connect(bridge.path); sock.sendall(json.dumps({'operation':'steering','token':token}).encode()+b'\n')
                with sock.makefile('rb') as stream: return json.loads(stream.readline())
        try:
            token=bridge.begin('one')
            self.assertEqual(ask(token),{'injectSteps':[{'userMessage':'for one'}]})
            self.assertEqual(ask('invalid'),{'injectSteps':[]})
            bridge.finish(token)
            self.assertEqual(ask(token),{'injectSteps':[]})
        finally: bridge.close()


if __name__=='__main__': unittest.main()
