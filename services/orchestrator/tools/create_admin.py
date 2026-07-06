#!/usr/bin/env python
import asyncio
import os
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db import AsyncSessionLocal, engine
from app.models import User

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

async def create_admin(username: str, email: str, password: str):
    async with AsyncSessionLocal() as session:
        # check existing
        res = await session.execute(select(User).where(User.username == username))
        user = res.scalar_one_or_none()
        if user:
            print("Admin user already exists")
            return
        hashed = pwd_context.hash(password)
        new = User(username=username, email=email, hashed_password=hashed)
        session.add(new)
        await session.commit()
        print("Admin user created")

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--username', default='admin')
    parser.add_argument('--email', default='admin@example.com')
    parser.add_argument('--password', default='adminpassword')
    args = parser.parse_args()
    asyncio.run(create_admin(args.username, args.email, args.password))
