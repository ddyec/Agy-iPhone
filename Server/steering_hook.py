#!/usr/bin/env python3
"""Official Pre/PostInvocation userMessage injection; never alters permissions."""
import json
import os
import socket
import sys


def invoke():
    # Consume the hook input so a parent writer cannot block on a full pipe.
    sys.stdin.buffer.read(256*1024+1)
    with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as connection:
        connection.settimeout(10)
        connection.connect(os.environ['AGY_IPHONE_REVIEW_SOCKET'])
        connection.sendall(json.dumps({'operation':'steering','token':os.environ['AGY_IPHONE_RUN_TOKEN']}).encode()+b'\n')
        with connection.makefile('rb') as stream: reply=json.loads(stream.readline(2*1024*1024))
    steps=reply.get('injectSteps',[])
    result={'injectSteps':steps} if steps else {}
    if steps and '--after' in sys.argv: result['terminationBehavior']='force_continue'
    return result


if __name__=='__main__':
    try: output=invoke()
    except Exception: output={}
    print(json.dumps(output,ensure_ascii=False))
