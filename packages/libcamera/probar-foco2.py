#!/usr/bin/env python3
import libcamera as lc, subprocess, time
cm = lc.CameraManager.singleton()
cam = [c for c in cm.cameras if 'i2c-bus@0' in c.id][0]
cam.acquire()
cfg = cam.generate_configuration([lc.StreamRole.Viewfinder])
cam.configure(cfg)
stream = cfg.at(0).stream
alloc = lc.FrameBufferAllocator(cam); alloc.allocate(stream)
bufs = alloc.buffers(stream)
cam.start({lc.controls.AfMode: lc.controls.AfModeEnum.Manual})

def chip():
    def rd(reg):
        r = subprocess.run(['sudo','i2ctransfer','-f','-y','12','w1@0x0c',reg,'r1'],
                           capture_output=True, text=True).stdout.strip()
        return int(r,16) if r.startswith('0x') else None
    m,l = rd('0x03'), rd('0x04')
    return None if m is None or l is None else m*256+l

for i,d in enumerate((7.0, 0.0, 3.5, 0.0)):
    r = cam.create_request()
    r.add_buffer(stream, bufs[i % len(bufs)])
    r.set_control(lc.controls.AfMode, lc.controls.AfModeEnum.Manual)
    r.set_control(lc.controls.LensPosition, d)
    cam.queue_request(r)
    time.sleep(2)
    print('pedido %.1f dioptrias -> esperado %d, el chip dice %s' % (d, round(d*1023/7.0), chip()))
cam.stop(); cam.release()
