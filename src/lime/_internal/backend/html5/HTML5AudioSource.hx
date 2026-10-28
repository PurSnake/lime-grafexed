package lime._internal.backend.html5;

import lime.media.AudioSource;
import lime.media.howlerjs.Howl;
#if lime_howlerjs
import lime.media.howlerjs.Howler;
#end

@:access(lime.media.AudioBuffer)
class HTML5AudioSource
{
	private var handle:Int = -1;
	private var loops:Int = 0;
	private var time:Float = 0;
	private var gain:Float = 1;
	private var pitch:Float = 1;
	private var pan:Float = 0;
	private var parent:AudioSource;

	public function new(parent:AudioSource):Void
	{
		this.parent = parent;
	}

	public function dispose():Void
	{
		stop();

		gain = 1;
		pitch = 1;
		pan = 0;
	}

	public function init():Void
	{
		// There isnt anything to intialize
	}

	public function play():Void
	{
		final buffer = parent.buffer;
		if (buffer == null || buffer.__srcHowl == null)
		{
			return;
		}

		final howl:Howl = buffer.__srcHowl;

		if (handle >= 0)
		{
			final previousHowl = findHowlForHandle(handle);
			final sound:Dynamic = previousHowl != null ? untyped previousHowl._soundById(handle) : null;

			if (previousHowl == howl && sound != null && sound._ended != true)
			{
				if (howl.state() == "loaded" && !howl.playing(handle))
				{
					howl.play(handle);
				}

				return;
			}

			final stopPrevious:Bool = previousHowl != null && previousHowl != howl && sound != null && sound._ended != true;
			releaseActiveHandle(stopPrevious);
			time = 0;
		}

		if (howl.state() == "unloaded")
		{
			howl.load();
		}

		startPlayback(howl);
	}

	public function pause():Void
	{
		final howl = getActiveHowl();
		if (howl != null && hasSound(howl, handle))
		{
			time = getCurrentTime();
			howl.pause(handle);
		}
		else if (handle >= 0)
		{
			handle = -1;
		}
	}

	public function stop():Void
	{
		releaseActiveHandle(true);
		time = 0;
	}

	private function startPlayback(howl:Howl):Void
	{
		if (parent.buffer == null || parent.buffer.__srcHowl != howl || handle != -1)
		{
			return;
		}

		final newHandle:Int = parent.buffer.__srcHowlerDefaultSprite != null
			? howl.play(parent.buffer.__srcHowlerDefaultSprite)
			: howl.play();

		if (newHandle < 0 || !hasSound(howl, newHandle))
		{
			return;
		}

		handle = newHandle;

		howl.once("end", howl_onEnd, newHandle);
		howl.once("playerror", howl_onError, newHandle);

		setCurrentTime(time);
		setGain(gain);
		setPitch(pitch);
		setPan(pan);
	}

	private function hasSound(howl:Howl, id:Int):Bool
	{
		if (id < 0)
		{
			return false;
		}

		final sound:Dynamic = untyped howl._soundById(id);
		return sound != null;
	}

	private function findHowlForHandle(id:Int):Howl
	{
		if (id < 0)
		{
			return null;
		}

		final buffer = parent.buffer;
		if (buffer != null && buffer.__srcHowl != null)
		{
			final currentHowl:Howl = buffer.__srcHowl;
			if (hasSound(currentHowl, id))
			{
				return currentHowl;
			}
		}

		#if lime_howlerjs
		final howls:Array<Howl> = untyped Howler._howls;
		if (howls != null)
		{
			for (howl in howls)
			{
				if (howl != null && hasSound(howl, id))
				{
					return howl;
				}
			}
		}
		#end

		return null;
	}

	private function getActiveHowl():Howl
	{
		if (handle < 0)
		{
			return null;
		}

		final howl = findHowlForHandle(handle);
		if (howl == null)
		{
			handle = -1;
		}

		return howl;
	}

	private function hasActiveSound():Bool
	{
		final howl = getActiveHowl();
		return howl != null && howl.state() == "loaded" && hasSound(howl, handle);
	}

	private function releaseActiveHandle(stopSound:Bool):Void
	{
		final id = handle;
		if (id >= 0)
		{
			final howl = findHowlForHandle(id);
			if (howl != null)
			{
				howl.off("playerror", howl_onError, id);
				howl.off("end", howl_onEnd, id);

				if (stopSound && hasSound(howl, id))
				{
					howl.stop(id);
				}
			}
		}

		handle = -1;
	}

	private function howl_onEnd(id:Int):Void
	{
		if (handle != id)
		{
			return;
		}

		final howl = findHowlForHandle(id);
		if (howl != null)
		{
			howl.off("playerror", howl_onError, id);
			howl.off("end", howl_onEnd, id);
		}

		handle = -1;
		time = 0;

		if (loops > 0)
		{
			loops--;
			play();
			return;
		}

		parent.onComplete.dispatch();
	}

	private function howl_onError(id:Int, err:Dynamic):Void
	{
		if (handle != id)
		{
			return;
		}

		releaseActiveHandle(false);
		time = 0;
	}

	public function getLength():Float
	{
		final howl = getActiveHowl();
		if (howl == null || howl.state() != "loaded" || !hasSound(howl, handle))
		{
			return 0;
		}

		return howl.duration(handle) * 1000.0;
	}

	public function getCurrentTime():Float
	{
		final howl = getActiveHowl();
		if (howl == null || howl.state() != "loaded" || !hasSound(howl, handle))
		{
			return time;
		}

		final seek:Float = howl.seek(handle) * 1000.0;
		if (seek == seek)
		{
			time = Math.max(0, seek);
		}

		return time;
	}

	public function setCurrentTime(value:Float):Float
	{
		if (value != value || value < 0)
		{
			value = 0;
		}

		time = value;

		final howl = getActiveHowl();
		if (howl != null && hasSound(howl, handle))
		{
			howl.seek(value / 1000.0, handle);
		}

		return time;
	}

	public function getGain():Float
	{
		final howl = getActiveHowl();
		return howl != null && hasActiveSound() ? howl.volume(handle) : gain;
	}

	public function setGain(value:Float):Float
	{
		gain = value;

		final howl = getActiveHowl();
		if (howl != null && hasSound(howl, handle))
		{
			howl.volume(value, handle);
		}

		return gain;
	}

	public function getPitch():Float
	{
		final howl = getActiveHowl();
		return howl != null && hasActiveSound() ? howl.rate(handle) : pitch;
	}

	public function setPitch(value:Float):Float
	{
		pitch = value;

		final howl = getActiveHowl();
		if (howl != null && hasSound(howl, handle))
		{
			howl.rate(value, handle);
		}

		return pitch;
	}

	public function getPan():Float
	{
		final howl = getActiveHowl();
		return howl != null && hasActiveSound() ? untyped howl.stereo(null, handle) : pan;
	}

	public function setPan(value:Float):Float
	{
		pan = value;

		final howl = getActiveHowl();
		if (howl != null && hasSound(howl, handle))
		{
			untyped howl.stereo(value, handle);
		}

		return pan;
	}

	public function getLoops():Int
	{
		return loops;
	}

	public function setLoops(value:Int):Int
	{
		return loops = value;
	}

	public function getPlaying():Bool
	{
		final howl = getActiveHowl();
		return howl != null && hasActiveSound() && howl.playing(handle);
	}
}
