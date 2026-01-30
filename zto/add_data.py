from gstgva import VideoFrame
from datetime import datetime, timezone
import json
def process_frame(frame: VideoFrame) -> bool:
    try:

        message = json.loads(frame.messages()[0])
        frame.remove_message(frame.messages()[0])
        message["system_timestamp"] = datetime.now(timezone.utc).isoformat(timespec='microseconds').replace('+00:00', 'Z')
        frame.add_message(json.dumps(message, ensure_ascii=False, separators=(",", ":")))
    except NameError:
        pass
    return True
