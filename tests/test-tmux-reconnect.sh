#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TMUX_TEST_ROOT="$ROOT"
python3 - <<'PYTEST'
"""Exercise SSH recovery without contacting real hosts or touching real sessions."""
import json
import os
from pathlib import Path
import pty
import select
import shutil
import shlex
import subprocess
import tempfile
import time
import unittest

ROOT = Path(os.environ["TMUX_TEST_ROOT"])
ZSH = shutil.which('zsh')


@unittest.skipUnless(ZSH, 'zsh is required')
class ReconnectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / 'calls'
        self.env = dict(os.environ, PATH=f'{self.root}:{os.environ["PATH"]}',
                        CALL_LOG=str(self.log), RESULTS='0')
        self.script = 'source "$1"; ssh() { exit 99; }; personal-dev "$2"'
        self.args = [ZSH, '-fc', self.script, 'test', str(ROOT / 'config/zsh/air.zsh'), 'dev']
        self.mock('ssh', '''import json,os,sys
from pathlib import Path
p=Path(os.environ['CALL_LOG'])
rows=p.read_text().splitlines() if p.exists() else []
n=sum(json.loads(x)[0]=='ssh' for x in rows)
with p.open('a') as f: f.write(json.dumps(['ssh',sys.argv[1:]])+'\\n')
results=os.environ['RESULTS'].split(',')
sys.exit(int(results[min(n,len(results)-1)]))
''')
        self.mock('sleep', '''import json,os,signal,sys
with open(os.environ['CALL_LOG'],'a') as f: f.write(json.dumps(['sleep',sys.argv[1:]])+'\\n')
if os.environ.get('CANCEL'): os.kill(os.getppid(),signal.SIGINT)
''')

    def mock(self, name, body):
        # Use the actual interpreter, avoiding platform launcher side effects.
        import sys
        p = self.root / name
        p.write_text(f'#!{sys.executable}\n'+body)
        p.chmod(0o755)

    def run_helper(self, results='0', name='dev'):
        self.env['RESULTS'] = results
        self.args[-1] = name
        return subprocess.run(self.args, env=self.env, capture_output=True, text=True, timeout=10)

    def calls(self, kind):
        return [row[1] for row in map(json.loads, self.log.read_text().splitlines()) if row[0] == kind]

    def test_normal_detach_stops_and_bypasses_wrapper(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls('ssh')), 1)
        self.assertEqual(self.calls('sleep'), [])
        self.assertNotIn('\x1b', result.stdout)

    def test_recovery_backoff_and_exact_attachment(self):
        result = self.run_helper('255,255,255,255,255,0', 'feature branch')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls('sleep'), [['2'], ['5'], ['10'], ['15'], ['15']])
        commands = [args[-1] for args in self.calls('ssh')]
        self.assertEqual(commands[0], 'tmux new -As feature\\ branch')
        self.assertTrue(all(shlex.split(c) == ['tmux', 'attach-session', '-t', '=feature branch'] for c in commands[1:]), commands)
        self.assertIn('ControlPath=none', self.calls('ssh')[0])

    def test_remote_failure_and_missing_session_stop(self):
        result = self.run_helper('255,1')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.calls('ssh')), 2)
        self.assertIn('Check the session', result.stderr)

    def test_name_is_shell_quoted(self):
        name = 'feature; touch /tmp/should-not-exist'
        result = self.run_helper('255,0', name)
        self.assertEqual(result.returncode, 0)
        for call in self.calls('ssh'):
            # Parse the command as shell arguments without executing its contents.
            import shlex
            self.assertEqual(shlex.split(call[-1])[-1], name if 'new -As' in call[-1] else '='+name)

    def test_cancel_wait_does_not_reconnect(self):
        self.env['CANCEL'] = '1'
        result = self.run_helper('255')
        self.assertEqual(result.returncode, 130, result.stderr)
        self.assertEqual(len(self.calls('ssh')), 1)

    def test_terminal_cleanup_on_cancel(self):
        self.env.update(RESULTS='255', CANCEL='1')
        pid, fd = pty.fork()
        if pid == 0:
            os.execve(ZSH, self.args, self.env)
        output = b''
        try:
            deadline = time.monotonic()+10
            while time.monotonic() < deadline:
                ready, _, _ = select.select([fd], [], [], .1)
                if ready:
                    try:
                        chunk = os.read(fd, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
            else:
                os.kill(pid, 9)
                self.fail('PTY helper did not exit')
            _, status = os.waitpid(pid, 0)
            self.assertEqual(os.waitstatus_to_exitcode(status), 130, output)
            for sequence in [b'\x1b[?1003l', b'\x1b[?1006l', b'\x1b[?1049l', b'\x1b[?25h']:
                self.assertIn(sequence, output)
        finally:
            os.close(fd)


if __name__ == '__main__':
    unittest.main()

PYTEST
