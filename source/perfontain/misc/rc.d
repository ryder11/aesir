module perfontain.misc.rc;

import
		std.conv,
		std.algorithm,

		std.experimental.allocator,
		std.experimental.allocator.mallocator,

		core.memory,

		tt.misc,
		tt.logger;


//version = LOG_RC;
alias Alloc = Mallocator.instance;

auto allocateRC(T, A...)(auto ref A args)
{
	auto m = Alloc.allocate(stateSize!T);
	GC.addRange(m.ptr, m.length);

	auto e = emplace!T(m, args);
	e.useAllocator = true;
	return e;

	//return new T(args);
}

class RCounted
{
	~this()
	{
		version(LOG_RC)
		{
			log(`%s destroying`, this);
		}

		debug
		{
			if(!_wasFreed)
			{
				log.error(`%s was never acquired`, this);
			}
		}
	}

final:
	bool isRcAlive()
	{
		return !!_refs;
	}

	void acquire()
	{
		debug
		{
			assert(!_wasFreed);
		}

		_refs++;

		version(LOG_RC)
		{
			log(`%s, %u refs`, this, _refs);
		}

		debug
		{
			rcLeaks[cast(void *)this]++;
		}
	}

	void release()
	{
		assert(_refs);

		version(LOG_RC)
		{
			log(`%s, %u refs`, this, _refs - 1);
		}

		if(!--_refs)
		{
			debug
			{
				_wasFreed = true;
				rcLeaks.remove(cast(void *)this);
			}

			auto b = useAllocator;
			auto sz = b ? typeid(this).initializer.length : 0;

			this.destroy;

			if(b)
			{
				auto p = (cast(void *)this)[0..sz];

				GC.removeRange(p.ptr);
				Alloc.deallocate(p);
			}
		}
		else debug
		{
			rcLeaks[cast(void *)this]--;
		}
	}

	bool useAllocator;
private:
	uint _refs;

	debug
	{
		bool _wasFreed;
	}
}

struct RC(T)
{
	this(T p)
	{
		if(p)
		{
			_rcElem = p;
			p.acquire;
		}
	}

	~this()
	{
		if(_rcElem)
		{
			_rcElem.release;
		}
	}

	this(this)
	{
		if(_rcElem)
		{
			_rcElem.acquire;
		}
	}

	T opAssign(T p)
	{
		assert(!p || _rcElem ! is p);

		if(_rcElem)
		{
			_rcElem.release;
		}

		_rcElem = p;

		if(_rcElem)
		{
			_rcElem.acquire;
		}

		return p;
	}

	T _rcElem;
	alias _rcElem this;
}

struct RCArray(T)
{
	this(T[] u)
	{
		opAssign(u);
	}

	this(this)
	{
		auto u = _arr;
		_arr = null;

		opAssign(u);
	}

	~this()
	{
		clear;
	}

	void clear()
	{
		releaseAll;
		resize(0);
	}

	void popBack()
	{
		back.release;
		resize(length - 1);
	}

	void remove(T t)
	{
		auto idx = _arr.countUntil!(a => a is t);

		_arr[idx].release;
		_arr.remove(idx);

		resize(length - 1);
	}

	void opIndexAssign(T p, size_t idx)
	{
		_arr[idx].release;
		_arr[idx] = p;

		p.acquire;
	}

	void opOpAssign(string op : `~`)(T p)
	{
		resize(length + 1);

		p.acquire;
		_arr[$ - 1] = p;
	}

	void opAssign(T[] u)
	{
		releaseAll;
		resize(u.length);

		_arr[] = u[];
		acquireAll;
	}

	inout front()
	{
		return _arr[0];
	}

	inout back()
	{
		return _arr[$ - 1];
	}

	inout opIndex(size_t idx)
	{
		return _arr[idx];
	}

	inout data()
	{
		return _arr;
	}

	inout opSlice()
	{
		return _arr;
	}

	inout opSlice(size_t start, size_t end)
	{
		return _arr[start..end];
	}

	const length()
	{
		return cast(uint)_arr.length;
	}

	const opDollar()
	{
		return length;
	}

private:
	void resize(size_t len)
	{
		if(_arr.ptr)
		{
			GC.removeRange(_arr.ptr);
		}

		if(len)
		{
			void[] u = _arr;

			auto b = Alloc.reallocate(u, len * size_t.sizeof);
			assert(b);

			GC.addRange(u.ptr, u.length);
			_arr = u.as!T;
		}
		else if(_arr.ptr)
		{
			Alloc.deallocate(_arr);
			_arr = null;
		}

		//_arr.length = len;
	}

	void acquireAll()
	{
		_arr.each!(a => a.acquire);
	}

	void releaseAll()
	{
		_arr.each!(a => a.release);
	}

	T[] _arr;
}

auto asRC(T)(T p)
{
	return RC!T(p);
}

void logLeaks()
{
	debug
	{
		if(rcLeaks.length)
		{
			log.error(`reference counting leaks:`);
			log.ident++;

			foreach(k, v; rcLeaks)
			{
				log.warning(`%s - %u refs`, (cast(Object)k).toString, v);
			}

			log.ident--;
		}
		else
		{
			log.info(`no reference counting leaks are found`);
		}
	}
}

private
{
	debug
	{
		uint[void *] rcLeaks;
	}
}
